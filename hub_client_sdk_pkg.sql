CREATE OR REPLACE PACKAGE hub_client_sdk_pkg AS
    
    -- Public Types for JSON Builder
    TYPE t_header_rec IS RECORD (
        name  VARCHAR2(255),
        value VARCHAR2(4000),
        seq   NUMBER
    );
    TYPE t_headers_tab IS TABLE OF t_header_rec;

    TYPE t_query_param_rec IS RECORD (
        name  VARCHAR2(255),
        value VARCHAR2(4000)
    );
    TYPE t_query_params_tab IS TABLE OF t_query_param_rec;

    /**
     * Package: hub_client_sdk_pkg
     * Purpose: Provides an SDK for internal systems to easily integrate with the Shared Services Hub.
     *          Handles authentication and payload transmission via REST.
     * Environment: Oracle 26ai / APEX
     */

    -- Global Configuration Constants
    c_system_code CONSTANT VARCHAR2(100) := 'YOUR_SYSTEM_CODE';
    c_env_type    CONSTANT VARCHAR2(10)  := 'TEST';

    /**
     * Function: get_auth_token
     * Purpose: Retrieves a Bearer token from the Hub Security API.
     * Parameters:
     *   - p_hub_base_url:  IN VARCHAR2 (NotNull) - Base URL of the ORDS Hub (e.g., 'https://your-domain.com/ords/schema').
     *   - p_client_id:     IN VARCHAR2 (NotNull) - The registered Client ID.
     *   - p_client_secret: IN VARCHAR2 (NotNull) - The registered Client Secret.
     *   - p_expires_in:    OUT TIMESTAMP - The SYSTIMESTAMP when the token will expire.
     * Returns:
     *   - VARCHAR2 - Plaintext Bearer access token.
     * Pipelined Behavior:
     *   - Encodes Client ID and Secret to Base64 for the Authorization header.
     *   - Makes a POST request to {p_hub_base_url}/hub/security/token using global constants for system/env.
     *   - Parses the JSON response to extract the token.
     * Exceptions:
     *   - Propagates HTTP REST connection or parsing exceptions.
     */
    FUNCTION get_auth_token(
        p_hub_base_url  IN VARCHAR2,
        p_client_id     IN VARCHAR2,
        p_client_secret IN VARCHAR2,
        p_expires_in    OUT TIMESTAMP
    ) RETURN VARCHAR2;

    /**
     * Function: call_hub_endpoint
     * Purpose: Submits a JSON payload to the Hub Runtime Execution API.
     * Parameters:
     *   - p_hub_base_url: IN VARCHAR2 (NotNull) - Base URL of the ORDS Hub.
     *   - p_token:        IN VARCHAR2 (NotNull) - Bearer token obtained from get_auth_token.
     *   - p_request_json: IN CLOB     (NotNull) - Full JSON request payload.
     * Returns:
     *   - CLOB - The Hub's JSON response payload.
     * Pipelined Behavior:
     *   - Makes a POST request to {p_hub_base_url}/hub/runtime/execute.
     *   - Injects the Bearer token into the Authorization HTTP Header.
     * Exceptions:
     *   - Propagates HTTP REST connection exceptions.
     */
    FUNCTION call_hub_endpoint(
        p_hub_base_url IN VARCHAR2,
        p_token        IN VARCHAR2,
        p_request_json IN CLOB
    ) RETURN CLOB;

    /**
     * Function: execute_with_auth
     * Purpose: Convenience method that securely fetches the auth token (or reads from local cache) 
     *          and executes the request in a single call.
     * Parameters:
     *   - p_hub_base_url:  IN VARCHAR2 (NotNull) - Base URL of the ORDS Hub.
     *   - p_client_id:     IN VARCHAR2 (NotNull) - The registered Client ID.
     *   - p_client_secret: IN VARCHAR2 (NotNull) - The registered Client Secret.
     *   - p_request_json:  IN CLOB     (NotNull) - Full JSON request payload.
     * Returns:
     *   - CLOB - The Hub's JSON response payload.
     */
    FUNCTION execute_with_auth(
        p_hub_base_url  IN VARCHAR2,
        p_client_id     IN VARCHAR2,
        p_client_secret IN VARCHAR2,
        p_request_json  IN CLOB
    ) RETURN CLOB;

    /**
     * Function: build_and_execute_request
     * Purpose: Constructs the standard Hub JSON payload from relational parameters and executes the request.
     * Parameters:
     *   - p_system_code:   IN VARCHAR2
     *   - p_environment:   IN VARCHAR2
     *   - p_flow_type:     IN VARCHAR2
     *   - p_provider_code: IN VARCHAR2
     *   - p_end_point:     IN VARCHAR2
     *   - p_http_method:   IN VARCHAR2
     *   - p_internal_code: IN VARCHAR2
     *   - p_headers:       IN hub_headers_tab
     *   - p_query_params:  IN hub_query_params_tab
     *   - p_body:          IN CLOB
     * Returns:
     *   - CLOB containing the Hub's JSON response payload
     */
    FUNCTION build_and_execute_request(
        p_hub_base_url  IN VARCHAR2,
        p_client_id     IN VARCHAR2,
        p_client_secret IN VARCHAR2,
        p_provider_code IN VARCHAR2,
        p_end_point     IN VARCHAR2,
        p_http_method   IN VARCHAR2,
        p_internal_code IN VARCHAR2,
        p_system_code   IN VARCHAR2 DEFAULT c_system_code,
        p_environment   IN VARCHAR2 DEFAULT c_env_type,
        p_flow_type     IN VARCHAR2 DEFAULT 'SYNC',
        p_headers       IN t_headers_tab DEFAULT NULL,
        p_query_params  IN t_query_params_tab DEFAULT NULL,
        p_body          IN CLOB DEFAULT NULL
    ) RETURN CLOB;

END hub_client_sdk_pkg;
/

CREATE OR REPLACE PACKAGE BODY hub_client_sdk_pkg AS

    FUNCTION get_auth_token(
        p_hub_base_url  IN VARCHAR2,
        p_client_id     IN VARCHAR2,
        p_client_secret IN VARCHAR2,
        p_expires_in    OUT TIMESTAMP
    ) RETURN VARCHAR2 IS
        l_response_clob CLOB;
        l_res_json      JSON_OBJECT_T;
        l_auth_header   VARCHAR2(32767);
        l_token         VARCHAR2(32767);
    BEGIN
        -- Generate Auth Header (Encoded Credentials)
        l_auth_header := REGEXP_REPLACE(
                           utl_raw.cast_to_varchar2(
                               utl_encode.base64_encode(
                                   utl_raw.cast_to_raw(p_client_id || ':' || p_client_secret)
                               )
                           ), '[[:space:]]', ''
                       );

        -- Clear any existing headers from previous calls
        apex_web_service.g_request_headers.delete;
        
        -- Set HTTP Headers
        apex_web_service.g_request_headers(1).name := 'Content-Type';
        apex_web_service.g_request_headers(1).value := 'application/json';
        apex_web_service.g_request_headers(2).name := 'Authorization';
        apex_web_service.g_request_headers(2).value := l_auth_header;
        apex_web_service.g_request_headers(3).name := 'systemCode';
        apex_web_service.g_request_headers(3).value := c_system_code;
        apex_web_service.g_request_headers(4).name := 'environmentType';
        apex_web_service.g_request_headers(4).value := c_env_type;

        -- Execute REST Call
        l_response_clob := apex_web_service.make_rest_request(
            p_url         => rtrim(p_hub_base_url, '/') || '/hub/security/token',
            p_http_method => 'POST',
            p_body        => empty_clob()
        );

        -- Check HTTP Status
        IF apex_web_service.g_status_code = 200 THEN
            l_res_json := JSON_OBJECT_T(l_response_clob);
            l_token := l_res_json.get_string('token');
            p_expires_in := l_res_json.get_timestamp('expiresIn');
            RETURN l_token;
        ELSE
            -- Raise application error with the response message for debugging
            raise_application_error(-20001, 'Token API Failed with HTTP ' || apex_web_service.g_status_code || ': ' || dbms_lob.substr(l_response_clob, 3000, 1));
        END IF;
    END get_auth_token;

    FUNCTION call_hub_endpoint(
        p_hub_base_url IN VARCHAR2,
        p_token        IN VARCHAR2,
        p_request_json IN CLOB
    ) RETURN CLOB IS
        l_response_clob CLOB;
    BEGIN
        -- Clear any existing headers
        apex_web_service.g_request_headers.delete;
        
        -- Set HTTP Headers
        apex_web_service.g_request_headers(1).name := 'Content-Type';
        apex_web_service.g_request_headers(1).value := 'application/json';
        apex_web_service.g_request_headers(2).name := 'Authorization';
        apex_web_service.g_request_headers(2).value := 'Bearer ' || p_token;

        -- Execute REST Call to Runtime Execute Endpoint
        l_response_clob := apex_web_service.make_rest_request(
            p_url         => rtrim(p_hub_base_url, '/') || '/hub/runtime/execute',
            p_http_method => 'POST',
            p_body        => p_request_json
        );

        -- HTTP Status can be checked using apex_web_service.g_status_code if needed by the calling application
        RETURN l_response_clob;
    END call_hub_endpoint;

    FUNCTION execute_with_auth(
        p_hub_base_url  IN VARCHAR2,
        p_client_id     IN VARCHAR2,
        p_client_secret IN VARCHAR2,
        p_request_json  IN CLOB
    ) RETURN CLOB IS
        l_token      VARCHAR2(32767);
        l_expires_in TIMESTAMP;
        l_response   CLOB;
    BEGIN
        -- ==============================================================================
        -- TODO: Token Caching Logic (Internal System Developer Implementation)
        -- ==============================================================================
        -- Here you should read the token from your local table to avoid redundant auth calls.
        --
        -- Example implementation:
        --
        -- BEGIN
        --     SELECT access_token INTO l_token FROM local_hub_tokens 
        --     WHERE system_code = c_system_code AND environment_type = c_env_type AND expiry_date > SYSDATE;
        -- EXCEPTION
        --     WHEN NO_DATA_FOUND THEN
        --         l_token := NULL;
        -- END;
        --
        -- IF l_token IS NULL THEN
        --     l_token := get_auth_token(p_hub_base_url, p_client_id, p_client_secret, l_expires_in);
        --     
        --     -- Update your local tokens table here
        --     -- MERGE INTO local_hub_tokens ...
        -- END IF;
        -- ==============================================================================
        
        -- Default Implementation (Fetches new token for every call unless cached above)
        l_token := get_auth_token(
            p_hub_base_url  => p_hub_base_url,
            p_client_id     => p_client_id,
            p_client_secret => p_client_secret,
            p_expires_in    => l_expires_in
        );

        -- Execute the actual API call
        l_response := call_hub_endpoint(
            p_hub_base_url => p_hub_base_url,
            p_token        => l_token,
            p_request_json => p_request_json
        );
        
        RETURN l_response;
    END execute_with_auth;

    FUNCTION build_and_execute_request(
        p_hub_base_url  IN VARCHAR2,
        p_client_id     IN VARCHAR2,
        p_client_secret IN VARCHAR2,
        p_provider_code IN VARCHAR2,
        p_end_point     IN VARCHAR2,
        p_http_method   IN VARCHAR2,
        p_internal_code IN VARCHAR2,
        p_system_code   IN VARCHAR2 DEFAULT c_system_code,
        p_environment   IN VARCHAR2 DEFAULT c_env_type,
        p_flow_type     IN VARCHAR2 DEFAULT 'SYNC',
        p_headers       IN t_headers_tab DEFAULT NULL,
        p_query_params  IN t_query_params_tab DEFAULT NULL,
        p_body          IN CLOB DEFAULT NULL
    ) RETURN CLOB IS
        l_request          JSON_OBJECT_T := JSON_OBJECT_T();
        l_request_json     CLOB;
        l_details_arr      JSON_ARRAY_T  := JSON_ARRAY_T();
        l_detail           JSON_OBJECT_T := JSON_OBJECT_T();
        l_headers_arr      JSON_ARRAY_T  := JSON_ARRAY_T();
        l_query_params_arr JSON_ARRAY_T  := JSON_ARRAY_T();
        l_header           JSON_OBJECT_T;
        l_param            JSON_OBJECT_T;
    BEGIN
        l_request.put('system_code', p_system_code);
        l_request.put('environment', p_environment);
        l_request.put('flow_type', p_flow_type);
        l_request.put('provider_code', p_provider_code);
        l_request.put('end_point', p_end_point);
        l_request.put('http_method', p_http_method);

        l_detail.put('internal_code', p_internal_code);

        -- Build Headers
        IF p_headers IS NOT NULL AND p_headers.COUNT > 0 THEN
            FOR i IN 1..p_headers.COUNT LOOP
                l_header := JSON_OBJECT_T();
                l_header.put('name', p_headers(i).name);
                l_header.put('value', p_headers(i).value);
                l_header.put('seq', p_headers(i).seq);
                l_headers_arr.append(l_header);
            END LOOP;
        END IF;
        l_detail.put('headers', l_headers_arr);

        -- Build Query Params
        IF p_query_params IS NOT NULL AND p_query_params.COUNT > 0 THEN
            FOR i IN 1..p_query_params.COUNT LOOP
                l_param := JSON_OBJECT_T();
                l_param.put('name', p_query_params(i).name);
                l_param.put('value', p_query_params(i).value);
                l_query_params_arr.append(l_param);
            END LOOP;
        END IF;
        l_detail.put('query_params', l_query_params_arr);

        -- Add Body
        IF p_body IS NOT NULL THEN
            -- Safely parse the CLOB as JSON and attach it
            l_detail.put('body', JSON_ELEMENT_T.parse(p_body));
        ELSE
            l_detail.put('body', JSON_OBJECT_T());
        END IF;

        l_details_arr.append(l_detail);
        l_request.put('request_details', l_details_arr);

        l_request_json := l_request.to_clob();

        RETURN execute_with_auth(
            p_hub_base_url  => p_hub_base_url,
            p_client_id     => p_client_id,
            p_client_secret => p_client_secret,
            p_request_json  => l_request_json
        );
    END build_and_execute_request;

END hub_client_sdk_pkg;
/
