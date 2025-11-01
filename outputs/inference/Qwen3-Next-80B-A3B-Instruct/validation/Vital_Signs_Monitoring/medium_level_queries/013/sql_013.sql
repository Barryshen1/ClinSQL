WITH spO2_first_48 AS (
  SELECT 
    i.stay_id,
    i.hadm_id,
    AVG(ce.valuenum) AS avg_spo2_first_48
  FROM physionet-data.mimiciv_3_1_icu.icustays i
  INNER JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON i.subject_id = p.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_icu.chartevents ce
    ON i.stay_id = ce.stay_id
  INNER JOIN physionet-data.mimiciv_3_1_icu.d_items di
    ON ce.itemid = di.itemid
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
    AND di.label = 'SpO2'
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 0 AND 100
    AND ce.charttime >= i.intime
    AND ce.charttime <= i.intime + INTERVAL '48' HOUR
  GROUP BY i.stay_id, i.hadm_id
),
aki_flag AS (
  SELECT DISTINCT
    i.stay_id,
    CASE 
      WHEN di.icd_code LIKE 'N17%' AND di.icd_version = 10 THEN 1
      ELSE 0
    END AS has_aki
  FROM physionet-data.mimiciv_3_1_icu.icustays i
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
    ON i.hadm_id = di.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses ddi
    ON di.icd_code = ddi.icd_code AND di.icd_version = ddi.icd_version
  WHERE di.icd_version = 10
),
spO2_with_aki AS (
  SELECT 
    s.stay_id,
    s.avg_spo2_first_48,
    COALESCE(a.has_aki, 0) AS has_aki
  FROM spO2_first_48 s
  LEFT JOIN aki_flag a ON s.stay_id = a.stay_id
),
categorized AS (
  SELECT 
    CASE 
      WHEN avg_spo2_first_48 < 90 THEN '<90'
      WHEN avg_spo2_first_48 >= 90 AND avg_spo2_first_48 <= 92 THEN '90-92'
      WHEN avg_spo2_first_48 >= 93 AND avg_spo2_first_48 <= 95 THEN '93-95'
      WHEN avg_spo2_first_48 > 95 THEN '>95'
    END AS spo2_category,
    has_aki
  FROM spO2_with_aki
)
SELECT 
  spo2_category,
  COUNT(*) AS patient_count,
  AVG(has_aki) AS aki_rate
FROM categorized
WHERE spo2_category IS NOT NULL
GROUP BY spo2_category
ORDER BY spo2_category;