WITH PatientDemographics AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age AS age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
),
ICUStays AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    ic.los AS icu_los
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS ic
),
HospitalAdmissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
),
ICUProcedures AS (
  SELECT
    pe.subject_id,
    pe.hadm_id,
    pe.stay_id,
    pe.starttime,
    pe.endtime,
    pe.itemid
  FROM
    `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
),
ProcedureLabels AS (
  SELECT
    di.itemid,
    di.label
  FROM
    `physionet-data.mimiciv_3_1_icu.d_items` AS di
  WHERE
    di.category = 'Procedure'
),
ProcedureCounts AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    COUNT(pe.itemid) AS procedure_count
  FROM
    ICUStays AS ic
    JOIN ICUProcedures AS pe ON ic.stay_id = pe.stay_id
    JOIN ProcedureLabels AS pl ON pe.itemid = pl.itemid
  WHERE
    pe.starttime BETWEEN ic.intime AND TIMESTAMP_ADD(ic.intime, INTERVAL 48 HOUR)
  GROUP BY
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id
),
PatientFilters AS (
  SELECT
    pd.subject_id,
    ha.hadm_id,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    ic.icu_los,
    ha.hospital_expire_flag,
    pc.procedure_count
  FROM
    PatientDemographics AS pd
    JOIN HospitalAdmissions AS ha ON pd.subject_id = ha.subject_id
    JOIN ICUStays AS ic ON ha.hadm_id = ic.hadm_id
    JOIN ProcedureCounts AS pc ON ic.stay_id = pc.stay_id
  WHERE
    pd.gender = 'M'
    AND pd.age BETWEEN 37 AND 47
    AND ic.stay_id IN (
      SELECT
        MIN(stay_id)
      FROM
        `physionet-data.mimiciv_3_1_icu.icustays`
      WHERE
        subject_id = pd.subject_id
      GROUP BY
        subject_id
    )
),
ProcedureQuintiles AS (
  SELECT
    pf.subject_id,
    pf.hadm_id,
    pf.stay_id,
    pf.intime,
    pf.outtime,
    pf.icu_los,
    pf.hospital_expire_flag,
    pf.procedure_count,
    NTILE(5) OVER (ORDER BY pf.procedure_count) AS procedure_quintile
  FROM
    PatientFilters AS pf
)
SELECT
  procedure_quintile,
  AVG(procedure_count) AS mean_procedure_count,
  AVG(icu_los) AS mean_icu_los,
  AVG(hospital_expire_flag) AS hospital_mortality
FROM
  ProcedureQuintiles
GROUP BY
  procedure_quintile
ORDER BY
  procedure_quintile;