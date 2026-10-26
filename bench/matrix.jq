split("\n")[:-1]
| map(split(" ") | [(.[0] | tonumber), (.[1] | tonumber)])
| sort
