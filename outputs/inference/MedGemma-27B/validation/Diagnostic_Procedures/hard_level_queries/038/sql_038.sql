WITH PatientCohort AS (
  -- Select patients matching the criteria: 65-year-old man, male, age 60-70, intracranial hemorrhage, first ICU stay
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    ic.los
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS ic
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p ON ic.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 60 AND 70
    AND ic.stay_id IN (
      -- Find the first ICU stay for each patient
      SELECT
        MIN(stay_id)
      FROM
        `physionet-data.mimiciv_3_1_icu.icustays`
      WHERE
        subject_id = ic.subject_id
      GROUP BY
        subject_id
    )
    AND ic.subject_id IN (
      -- Find patients with intracranial hemorrhage (ICD-10 code I60-I69)
      SELECT
        d.subject_id
      FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
      WHERE
        d.icd_code LIKE 'I6%' -- Intracranial hemorrhage codes
        AND d.seq_num = 1 -- Assuming the first diagnosis is the primary one
    )
),
ProcedureBurden AS (
  -- Calculate the number of procedures performed within the first 72 hours of the ICU stay
  SELECT
    pc.subject_id,
    pc.stay_id,
    COUNT(pe.itemid) AS procedure_count
  FROM
    PatientCohort AS pc
    JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe ON pc.subject_id = pe.subject_id AND pc.stay_id = pe.stay_id
  WHERE
    pe.starttime BETWEEN pc.intime AND TIMESTAMP_ADD(pc.intime, INTERVAL 72 HOUR)
  GROUP BY
    pc.subject_id,
    pc.stay_id
),
Percentiles AS (
  -- Calculate the 75th percentile of procedure burden
  SELECT
    PERCENTILE_CONT(0.75, procedure_count) AS p75_procedure_burden
  FROM
    ProcedureBurden
),
GeneralICUPopulation AS (
  -- Calculate mean ICU LOS and hospital mortality for the general ICU population
  SELECT
    AVG(ic.los) AS mean_icu_los,
    AVG(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS hospital_mortality
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS ic
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a ON ic.hadm_id = a.hadm_id
)
-- Final result: Combine the 75th percentile of procedure burden for the cohort and the statistics for the general ICU population
SELECT
  p.p75_procedure_burden,
  g.mean_icu_los,
  g.hospital_mortality
FROM
  Percentiles AS p,
  GeneralICUPopulation AS g;