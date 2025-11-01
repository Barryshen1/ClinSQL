WITH acs_admissions AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE 
    ( (d.icd_version = 9 AND (d.icd_code LIKE '410%' OR d.icd_code LIKE '411%' )) 
      OR (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%' OR d.icd_code LIKE 'I200%' OR d.icd_code LIKE 'I201%'))
    )
),
eligible_patients AS (
  SELECT p.subject_id, p.anchor_age, p.gender, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN acs_admissions acs
    ON a.hadm_id = acs.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 79 AND 89
),
troponin_t_labs AS (
  SELECT le.subject_id, le.hadm_id, le.charttime, le.valuenum, le.valueuom
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON le.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%troponin t%'
    AND le.valuenum IS NOT NULL
    AND le.valueuom = 'ng/mL'
),
first_trop_per_admit AS (
  SELECT t.subject_id, t.hadm_id, t.valuenum, t.charttime
  FROM troponin_t_labs t
  JOIN eligible_patients ep
    ON t.subject_id = ep.subject_id
    AND t.hadm_id = ep.hadm_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY t.hadm_id ORDER BY t.charttime ASC) = 1
),
categorised AS (
  SELECT
    subject_id,
    hadm_id,
    valuenum,
    CASE
      WHEN valuenum <= 0.01 THEN 'Normal'
      WHEN valuenum <= 0.03 THEN 'Borderline'
      ELSE 'Elevated'
    END AS category
  FROM first_trop_per_admit
),
stats AS (
  SELECT
    category,
    COUNT(*) AS cnt,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS pct,
    ROUND(AVG(valuenum), 4) AS mean_trop,
    APPROX_QUANTILES(valuenum, 4)[OFFSET(2)] AS median_trop,
    ROUND(APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] 
          - APPROX_QUANTILES(valuenum, 4)[OFFSET(1)], 4) AS iqr_trop
  FROM categorised
  GROUP BY category
)
SELECT *
FROM stats
ORDER BY 
  CASE category 
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Elevated' THEN 3
  END;