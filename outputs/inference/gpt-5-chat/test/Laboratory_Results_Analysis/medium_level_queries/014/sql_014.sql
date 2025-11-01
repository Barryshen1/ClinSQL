WITH acs_patients AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.subject_id = diag.subject_id
    AND adm.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON diag.icd_code = dd.icd_code
    AND diag.icd_version = dd.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 79 AND 89
    AND (
      LOWER(dd.long_title) LIKE '%acute myocardial infarction%'
      OR LOWER(dd.long_title) LIKE '%unstable angina%'
      OR LOWER(dd.long_title) LIKE '%acute ischemic heart%'
      OR LOWER(dd.long_title) LIKE '%acute coronary%'
    )
),
troponin_labs AS (
  SELECT le.labevent_id, le.subject_id, le.hadm_id, le.charttime, le.valuenum
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
    charttime,
    valuenum AS troponin_t
  FROM (
    SELECT
      tl.*,
      ROW_NUMBER() OVER (
        PARTITION BY tl.subject_id, tl.hadm_id 
        ORDER BY tl.charttime ASC, tl.labevent_id
      ) AS rn
    FROM troponin_labs tl
  )
  WHERE rn = 1
),
categorized AS (
  SELECT
    ft.subject_id,
    ft.hadm_id,
    CASE
      WHEN ft.troponin_t < 0.01 THEN 'Normal'
      WHEN ft.troponin_t <= 0.03 THEN 'Borderline'
      ELSE 'Elevated'
    END AS category
  FROM first_trop ft
)
SELECT
  category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage
FROM categorized c
JOIN acs_patients a
  ON c.subject_id = a.subject_id
  AND c.hadm_id = a.hadm_id
GROUP BY category
ORDER BY category;