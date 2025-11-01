WITH PatientCohort AS (
  -- Select patients matching the criteria: female, age 50-60, intracranial hemorrhage
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    ic.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS ic
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON ic.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON ic.subject_id = di.subject_id AND ic.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND d.long_title LIKE '%intracranial hemorrhage%'
    AND ic.intime IS NOT NULL
    AND ic.outtime IS NOT NULL
    AND ic.los > 0
),

ProcedureBurden AS (
  -- Calculate procedure burden for each patient in the cohort during the first 72 hours of ICU stay
  SELECT
    pc.subject_id,
    pc.stay_id,
    COUNT(pe.itemid) AS procedure_count
  FROM PatientCohort AS pc
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
    ON pc.subject_id = pe.subject_id AND pc.stay_id = pe.stay_id
  WHERE
    pe.starttime BETWEEN pc.intime AND TIMESTAMP_ADD(pc.intime, INTERVAL 72 HOUR)
  GROUP BY
    pc.subject_id,
    pc.stay_id
),

GeneralICUPopulation AS (
  -- Select all ICU patients for comparison
  SELECT
    ic.subject_id,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    ic.los,
    h.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS ic
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS h
    ON ic.hadm_id = h.hadm_id
  WHERE
    ic.intime IS NOT NULL
    AND ic.outtime IS NOT NULL
    AND ic.los > 0
),

CohortStats AS (
  -- Calculate percentiles of procedure burden for the cohort
  SELECT
    APPROX_QUANTILES(pb.procedure_count, [0.25, 0.5, 0.9]) AS procedure_burden_percentiles
  FROM ProcedureBurden AS pb
),

CohortMortalityLOS AS (
  -- Calculate average ICU LOS and mortality for the cohort
  SELECT
    AVG(gip.los) AS avg_icu_los,
    AVG(CAST(gip.hospital_expire_flag AS INT64)) AS avg_mortality -- Cast to INT64 for AVG calculation
  FROM GeneralICUPopulation AS gip
  WHERE gip.subject_id IN (SELECT subject_id FROM PatientCohort) -- Filter GeneralICUPopulation to only include cohort patients
),

GeneralStats AS (
  -- Calculate average ICU LOS and mortality for the general ICU population
  SELECT
    AVG(gip.los) AS avg_icu_los,
    AVG(CAST(gip.hospital_expire_flag AS INT64)) AS avg_mortality -- Cast to INT64 for AVG calculation
  FROM GeneralICUPopulation AS gip
)

-- Final result combining cohort stats and comparison stats
SELECT
  cs.procedure_burden_percentiles,
  cl.avg_icu_los AS cohort_avg_icu_los,
  cl.avg_mortality AS cohort_avg_mortality,
  gs.avg_icu_los AS general_avg_icu_los,;