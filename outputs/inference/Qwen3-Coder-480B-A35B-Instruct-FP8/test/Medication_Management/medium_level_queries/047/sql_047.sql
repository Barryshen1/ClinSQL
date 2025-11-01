WITH eligible_patients AS (
  SELECT DISTINCT
    p.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%diabetes%'
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%heart failure%'
    )
),

medications AS (
  SELECT
    ep.subject_id,
    ep.stay_id,
    ep.intime,
    ep.outtime,
    CASE
      WHEN LOWER(medication) LIKE '%insulin%' OR LOWER(medication) LIKE '%metformin%' THEN 'antidiabetic'
      WHEN LOWER(medication) LIKE '%metoprolol%' OR LOWER(medication) LIKE '%carvedilol%' THEN 'beta_blocker'
      WHEN LOWER(medication) LIKE '%lisinopril%' OR LOWER(medication) LIKE '%losartan%' OR LOWER(medication) LIKE '%sacubitril%' THEN 'acei_arb_arni'
      WHEN LOWER(medication) LIKE '%furosemide%' OR LOWER(medication) LIKE '%bumetanide%' THEN 'loop_diuretic'
    END AS drug_class,
    charttime
  FROM
    eligible_patients ep
  JOIN
    `physionet-data.mimiciv_3_1_hosp.emar` e ON ep.hadm_id = e.hadm_id
  WHERE
    e.charttime IS NOT NULL
),

drug_timings AS (
  SELECT
    subject_id,
    stay_id,
    drug_class,
    MAX(CASE WHEN charttime BETWEEN intime AND intime + INTERVAL 1 DAY THEN 1 ELSE 0 END) AS in_first_24h,
    MAX(CASE WHEN charttime BETWEEN outtime - INTERVAL 1 DAY AND outtime THEN 1 ELSE 0 END) AS in_last_24h
  FROM
    medications
  WHERE
    drug_class IS NOT NULL
  GROUP BY
    subject_id, stay_id, drug_class
),

drug_summary AS (
  SELECT
    drug_class,
    COUNT(*) AS total_patients,
    SUM(in_first_24h) AS count_first_24h,
    SUM(in_last_24h) AS count_last_24h,
    SUM(CASE WHEN in_first_24h = 1 AND in_last_24h = 1 THEN 1 ELSE 0 END) AS continued,
    SUM(CASE WHEN in_first_24h = 0 AND in_last_24h = 1 THEN 1 ELSE 0 END) AS initiated_late,
    SUM(CASE WHEN in_first_24h = 1 AND in_last_24h = 0 THEN 1 ELSE 0 END) AS discontinued
  FROM
    drug_timings
  GROUP BY
    drug_class
)

SELECT
  drug_class,
  ROUND(100.0 * count_first_24h / total_patients, 2) AS pct_first_24h,
  ROUND(100.0 * count_last_24h / total_patients, 2) AS pct_last_24h,
  continued,
  initiated_late,
  discontinued
FROM
  drug_summary
ORDER BY
  drug_class;