import { typedData, TypedDataRevision } from "starknet";
import { sessionTypes } from "../lib";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function printEncodeTypes(types: any) {
  for (const [typeName, typeFields] of Object.entries(types)) {
    if (typeName === "StarknetDomain") continue;
    console.log(`\n${typeName}:`);
    console.log(typeFields);
    const encodeType = typedData.encodeType(types, typeName, TypedDataRevision.ACTIVE);
    console.log(encodeType);
    // replace all " with \"
    console.log(encodeType.replace(/"/g, '\\"'));
  }
}

console.log("--------------------------------");
printEncodeTypes(sessionTypes);
