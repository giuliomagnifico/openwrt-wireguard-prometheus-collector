local function scrape()

        local f = assert(io.popen("uci show network | awk -F '[\.]' -v OFS='\t' '$3 ~ \"public_key=\" { print substr($3,13,44),$2 }'"))
        local names = {}
        for line in f:lines() do
                toks = line:gmatch("([^\t]*)\t?")
                names[toks()]=toks()
        end
        f:close()

        local f = assert(io.popen("wg show all dump", 'r'))
        local last_interface
        for line in f:lines() do
                toks = line:gmatch("([^\t]*)\t?")
                local labels = {
                        interface=toks(),
                        public_key=toks(),
                        preshared_key=toks(),
                        endpoint=toks(),
                        allowed_ips=toks()
                }
                labels["name"]=names[labels["public_key"]]
                labels["preshared_key"]=nil

                if last_interface == labels["interface"] then
                        metric("wireguard_latest_handshake_seconds", "gauge", labels, toks())
                        metric("wireguard_received_bytes_total", "counter", labels, toks())
                        metric("wireguard_sent_bytes_total", "counter", labels, toks())
                else
                        last_interface=labels["interface"]
                end
        end
        f:close()
end

return { scrape = scrape }
