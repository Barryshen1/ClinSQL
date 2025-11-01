WITH ami_cohort AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dic
    ON dic.icd_code = di.icd_code AND dic.icd_version = di.icd_version
  WHERE LOWER(p.gender) = 'f'
    AND p.anchor_age BETWEEN 40 AND 50
    AND LOWER(dic.long_title) LIKE '%myocardial infarction%'
),

initial_troponin AS (
  SELECT le.hadm_id, le.subject_id, le.charttime, le.valuenum, le.valueuom
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS li
    ON le.itemid = li.itemid
  WHERE LOWER(li.label) LIKE '%troponin t%'
    AND le.hadm_id IN (SELECT hadm_id FROM ami_cohort)
),

first_troponin AS (
  SELECT hadm_id, subject_id, charttime, valuenum, valueuom
  FROM (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime) AS rn
    FROM initial_troponin
  )
  WHERE rn = 1
)

SELECT
  COUNT(CASE WHEN category = 'normal' THEN 1 END) AS normal_count,
  COUNT(CASE WHEN category = 'borderline' THEN 1 END) AS borderline_count,
  COUNT(CASE WHEN category = 'elevated' THEN 1 END) AS elevated_count
FROM (
  SELECT hadm_id,
         CASE
           -- ng/mL units
           WHEN valueuom IN ('ng/mL','ng/ml','NG/ML','Ng/mL') THEN
             CASE
               WHEN valuenum < 0.01 THEN 'normal'
               WHEN valuenum <= 0.04 THEN 'borderline'
               ELSE 'elevated'
             END
           -- ng/L units
           WHEN valueuom IN ('ng/L','ng/l') THEN
             CASE
               WHEN valuenum < 10 THEN 'normal'
               WHEN valuenum <= 40 THEN 'borderline'
               ELSE 'elevated'
             END
           -- Fallback: default to ng/mL thresholds
           ELSE
             CASE
               WHEN valuenum < 0.01 THEN 'normal'
               WHEN valuenum <= 0.04 THEN 'borderline'
               ELSE 'elevated'
             END
         END AS category
  FROM first_troponin
  WHERE valuenum IS NOT NULL
) t;