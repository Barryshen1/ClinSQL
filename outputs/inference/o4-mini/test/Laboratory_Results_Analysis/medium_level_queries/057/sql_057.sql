WITH acs_adms AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%acute%'
    AND (
      LOWER(dd.long_title) LIKE '%myocardial infarction%'
      OR LOWER(dd.long_title) LIKE '%unstable angina%'
    )
),
troponin_events AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON le.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%troponin t%'
    AND le.valuenum IS NOT NULL
),
first_trop AS (
  SELECT
    subject_id,
    hadm_id,
    valuenum AS trop_value
  FROM troponin_events
  WHERE rn = 1
),
filtered AS (
  SELECT
    ft.subject_id,
    ft.hadm_id,
    ft.trop_value
  FROM first_trop ft
  JOIN acs_adms a
    USING(subject_id, hadm_id)
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    USING(subject_id, hadm_id)
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 79 AND 89
),
categorized AS (
  SELECT
    CASE
      WHEN trop_value <= 0.04 THEN 'normal'
      WHEN trop_value > 0.04 AND trop_value <= 0.1 THEN 'borderline'
      WHEN trop_value > 0.1 THEN 'elevated'
    END AS category
  FROM filtered
)
SELECT
  category,
  COUNT(*) AS admission_count
FROM categorized
GROUP BY category
ORDER BY category;