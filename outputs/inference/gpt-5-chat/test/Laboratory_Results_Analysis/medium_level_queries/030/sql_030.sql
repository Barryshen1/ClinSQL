WITH cohort AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.hadm_id = dx.hadm_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 64 AND 74
    AND (
      (dx.icd_version = 9 AND dx.icd_code LIKE '410%')
      OR (dx.icd_version = 10 AND (dx.icd_code LIKE 'I21%' OR dx.icd_code LIKE 'I22%'))
    )
),
hs_tnt_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
    AND LOWER(label) LIKE '%high%'
),
index_tnt AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime ASC, le.labevent_id ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN hs_tnt_items di
    ON le.itemid = di.itemid
  INNER JOIN cohort c
    ON le.hadm_id = c.hadm_id
  WHERE le.valuenum IS NOT NULL
)
, first_tnt AS (
  SELECT subject_id, hadm_id, valuenum
  FROM index_tnt
  WHERE rn = 1
)
, categorized AS (
  SELECT
    *,
    CASE
      WHEN valuenum <= 0.014 THEN 'Normal'
      WHEN valuenum <= 0.052 THEN 'Borderline'
      ELSE 'Myocardial Injury'
    END AS category
  FROM first_tnt
)
SELECT
  category,
  COUNT(*) AS n,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage
FROM categorized
GROUP BY category
ORDER BY category;