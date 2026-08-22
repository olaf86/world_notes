import {
  accountSafetyReplicationHandler,
  adminAccountSafetyReplicationHandler,
} from "./accountSafety";
import {
  GlobalReplicationHandlerRegistry,
  GlobalReplicationRuntime,
} from "./globalReplication";
import {
  publicProfileReplicationHandler,
  userEntitlementReplicationHandler,
} from "./profileEntitlementReplication";
import {socialEdgeReplicationHandler} from "./socialEdgeReplication";
import {userBlockReplicationHandler} from "./userBlockReplication";
import {
  WorldDatabaseConfig,
  WorldFirestoreDatabaseId,
  WorldFirestoreProvider,
} from "./platform/worldFirestoreProvider";
import {WORLD_CATALOG} from "./platform/worldCatalog";

const worldDatabases = WORLD_CATALOG.worlds.map((world) => ({
  worldId: world.worldId,
  databaseId: world.databaseId as WorldFirestoreDatabaseId,
})) satisfies readonly WorldDatabaseConfig[];

/** Shared production runtime used by triggers and synchronous bootstrap. */
export const productionGlobalReplicationRuntime: GlobalReplicationRuntime = {
  catalog: WORLD_CATALOG,
  firestore: new WorldFirestoreProvider(worldDatabases),
  handlers: new GlobalReplicationHandlerRegistry([
    publicProfileReplicationHandler,
    userEntitlementReplicationHandler,
    socialEdgeReplicationHandler,
    userBlockReplicationHandler,
    accountSafetyReplicationHandler,
    adminAccountSafetyReplicationHandler,
  ]),
};
