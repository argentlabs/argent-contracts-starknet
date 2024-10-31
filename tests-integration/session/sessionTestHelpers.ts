import { Contract } from "starknet";
import { AllowedMethod } from "../../lib";

export const singleMethodAllowList: (contract: string | Contract, selector: string) => AllowedMethod[] = (
  contract,
  selector,
) => [
  {
    "Contract Address": typeof contract === "string" ? contract : contract.address,
    selector,
  },
];
