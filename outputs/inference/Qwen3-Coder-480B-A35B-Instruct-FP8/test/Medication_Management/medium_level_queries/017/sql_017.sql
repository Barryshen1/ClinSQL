WITH cohort AS (
  SELECT
    p.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    i.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    i.hadm_id = a.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 37 AND 47
    AND i.los >= 6
    AND a.hospital_expire_flag = 0
),

diabetes_hf_admissions AS (
  SELECT DISTINCT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.intime,
    c.outtime
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    c.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON
    d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE
    (dd.long_title LIKE '%diabetes%' OR dd.long_title LIKE '%Diabetes%')
    OR (dd.long_title LIKE '%heart failure%' OR dd.long_title LIKE '%Heart Failure%')
),

drug_prescriptions AS (
  SELECT
    dh.stay_id,
    pr.drug,
    pr.starttime,
    pr.stoptime,
    dh.intime,
    dh.outtime,
    CASE
      WHEN LOWER(pr.drug) LIKE '%insulin%' OR LOWER(pr.drug) LIKE '%metformin%' THEN 'Antidiabetic'
      WHEN LOWER(pr.drug) LIKE '%metoprolol%' OR LOWER(pr.drug) LIKE '%carvedilol%' THEN 'Beta-blocker'
      WHEN LOWER(pr.drug) LIKE '%lisinopril%' OR LOWER(pr.drug) LIKE '%losartan%' OR LOWER(pr.drug) LIKE '%sacubitril%' THEN 'ACEi/ARB/ARNI'
      WHEN LOWER(pr.drug) LIKE '%furosemide%' OR LOWER(pr.drug) LIKE '%bumetanide%' OR LOWER(pr.drug) LIKE '%torsemide%' THEN 'Loop diuretic'
      ELSE NULL
    END AS drug_class
  FROM
    diabetes_hf_admissions dh
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  ON
    dh.hadm_id = pr.hadm_id
  WHERE
    pr.drug IS NOT NULL
),

drug_timings AS (
  SELECT
    stay_id,
    drug_class,
    starttime,
    stoptime,
    intime,
    outtime,
    CASE
      WHEN starttime BETWEEN intime AND TIMESTAMP_ADD(intime, INTERVAL 72 HOUR) THEN 'First72h'
      WHEN starttime BETWEEN TIMESTAMP_SUB(outtime, INTERVAL 72 HOUR) AND outtime THEN 'Final72h'
      ELSE 'Other'
    END AS time_window
  FROM
    drug_prescriptions
  WHERE
    drug_class IS NOT NULL
),

drug_usage AS (
  SELECT
    stay_id,
    drug_class,
    time_window,
    COUNT(*) AS drug_count
  FROM
    drug_timings
  WHERE
    time_window IN ('First72h', 'Final72h')
  GROUP BY
    stay_id, drug_class, time_window
),

drug_summary AS (
  SELECT
    drug_class,
    time_window,
    COUNT(DISTINCT stay_id) AS patient_count
  FROM
    drug_usage
  GROUP BY
    drug_class, time_window
),

total_patients AS (
  SELECT COUNT(DISTINCT stay_id) AS total FROM diabetes_hf_admissions
),

-- Initiated, continued, discontinued logic
drug_changes AS (
  SELECT
    stay_id,
    drug_class,
    MAX(CASE WHEN time_window = 'First72h' THEN 1 ELSE 0 END) AS in_first,
    MAX(CASE WHEN time_window = 'Final72h' THEN 1 ELSE 0 END) AS in_final
  FROM
    drug_usage
  GROUP BY
    stay_id, drug_class
),

change_summary AS (
  SELECT
    drug_class,
    SUM(CASE WHEN in_first = 1 AND in_final = 0 THEN 1 ELSE 0 END) AS discontinued,
    SUM(CASE WHEN in_first = 0 AND in_final = 1 THEN 1 ELSE 0 END) AS initiated,
    SUM(CASE WHEN in_first = 1 AND in_final = 1 THEN 1 ELSE 0 END) AS continued
  FROM
    drug_changes
  GROUP BY
    drug_class
)

SELECT
  ds.drug_class,
  ds.time_window,
  ds.patient_count,
  ROUND(100 * ds.patient_count / tp.total, 2) AS percent_patients,
  COALESCE(cs.initiated, 0) AS initiated,
  COALESCE(cs.continued, 0) AS continued,
  COALESCE(cs.discontinued, 0) AS discontinued
FROM
  drug_summary ds
CROSS JOIN
  total_patients tp
LEFT JOIN
  change_summary cs
ON
  ds.drug_class = cs.drug_class
ORDER BY
  ds.drug_class, ds.time_window;