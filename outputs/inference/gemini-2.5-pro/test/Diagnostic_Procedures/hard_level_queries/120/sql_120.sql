WITH
  ugib_hadm AS (
    -- Step 1: Identify all hospital admissions (hadm_id) with a diagnosis of Upper GI Bleeding
    SELECT DISTINCT
      hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      -- ICD-9 codes for Upper GI Bleeding
      (
        icd_version = 9
        AND (
          icd_code LIKE '531.0%' OR icd_code LIKE '531.2%' OR icd_code LIKE '531.4%' OR icd_code LIKE '531.6%' -- Gastric ulcer
          OR icd_code LIKE '532.0%' OR icd_code LIKE '532.2%' OR icd_code LIKE '532.4%' OR icd_code LIKE '532.6%' -- Duodenal ulcer
          OR icd_code LIKE '533.0%' OR icd_code LIKE '533.2%' OR icd_code LIKE '533.4%' OR icd_code LIKE '533.6%' -- Peptic ulcer
          OR icd_code LIKE '534.0%' OR icd_code LIKE '534.2%' OR icd_code LIKE '534.4%' OR icd_code LIKE '534.6%' -- Gastrojejunal ulcer
          OR icd_code IN ('578.0', '578.1', '578.9') -- Hematemesis, Melena, GI hemorrhage NOS
        )
      )
      OR
      -- ICD-10 codes for Upper GI Bleeding
      (
        icd_version = 10
        AND (
          icd_code IN (
            'K25.0', 'K25.1', 'K25.2', 'K25.4', 'K25.6', -- Gastric ulcer with hemorrhage/perf
            'K26.0', 'K26.1', 'K26.2', 'K26.4', 'K26.6', -- Duodenal ulcer with hemorrhage/perf
            'K27.0', 'K27.1', 'K27.2', 'K27.4', 'K27.6', -- Peptic ulcer with hemorrhage/perf
            'K28.0', 'K28.1', 'K28.2', 'K28.4', 'K28.6', -- Gastrojejunal ulcer with hemorrhage/perf
            'K29.01', -- Acute gastritis with bleeding
            'I85.01', -- Esophageal varices with bleeding
            'K92.0', -- Hematemesis
            'K92.1', -- Melena
            'K92.2' -- Gastrointestinal hemorrhage, unspecified
          )
        )
      )
  ),
  cohort_stays AS (
    -- Step 2: Define the patient cohort (Male, 74-84, UGIB) and select their first ICU stay
    SELECT
      p.subject_id,
      a.hadm_id,
      i.stay_id,
      i.intime,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a ON p.subject_id = a.subject_id
      INNER JOIN ugib_hadm AS u ON a.hadm_id = u.hadm_id
      INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i ON a.hadm_id = i.hadm_id
    WHERE
      p.gender = 'M'
      AND p.anchor_age BETWEEN 74 AND 84
    QUALIFY ROW_NUMBER() OVER (PARTITION BY a.hadm_id ORDER BY i.intime) = 1
  ),
  labs_72h AS (
    -- Step 3a: Count lab events in the first 72 hours of the ICU stay
    SELECT
      cs.hadm_id,
      COUNT(le.labevent_id) AS lab_count
    FROM
      cohort_stays AS cs
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le ON cs.hadm_id = le.hadm_id
    WHERE
      le.charttime BETWEEN cs.intime AND DATETIME_ADD(cs.intime, INTERVAL 72 HOUR)
    GROUP BY
      cs.hadm_id
  ),
  procs_72h AS (
    -- Step 3b: Count ICD procedures in the first 72 hours (approximated by 3 days)
    SELECT
      cs.hadm_id,
      COUNT(*) AS proc_count
    FROM
      cohort_stays AS cs
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pi ON cs.hadm_id = pi.hadm_id
    WHERE
      pi.chartdate BETWEEN DATE(cs.intime) AND DATE_ADD(DATE(cs.intime), INTERVAL 2 DAY)
    GROUP BY
      cs.hadm_id
  ),
  procs_total AS (
    -- Step 3c: Count all ICD procedures for the entire hospital admission
    SELECT
      hadm_id,
      COUNT(*) AS total_proc_count
    FROM
      `physionet-data.mimiciv_3_1_hosp.procedures_icd`
    GROUP BY
      hadm_id
  ),
  patient_metrics AS (
    -- Step 4: Combine metrics for each patient and calculate diagnostic intensity
    SELECT
      cs.hadm_id,
      cs.hospital_expire_flag,
      DATETIME_DIFF(cs.dischtime, cs.admittime, DAY) AS hospital_los_days,
      COALESCE(l.lab_count, 0) + COALESCE(p72.proc_count, 0) AS diagnostic_intensity,
      COALESCE(pt.total_proc_count, 0) AS total_procedure_count
    FROM
      cohort_stays AS cs
      LEFT JOIN labs_72h AS l ON cs.hadm_id = l.hadm_id
      LEFT JOIN procs_72h AS p72 ON cs.hadm_id = p72.hadm_id
      LEFT JOIN procs_total AS pt ON cs.hadm_id = pt.hadm_id
  ),
  patient_quartiles AS (
    -- Step 5: Stratify patients into quartiles based on diagnostic intensity
    SELECT
      *,
      NTILE(4) OVER (
        ORDER BY
          diagnostic_intensity
      ) AS quartile
    FROM
      patient_metrics
  )
-- Final Step: Aggregate metrics by quartile
SELECT
  quartile,
  AVG(total_procedure_count) AS mean_procedure_count,
  AVG(hospital_los_days) AS mean_hospital_los_days,
  AVG(hospital_expire_flag) AS in_hospital_mortality
FROM
  patient_quartiles
GROUP BY
  quartile
ORDER BY
  quartile;