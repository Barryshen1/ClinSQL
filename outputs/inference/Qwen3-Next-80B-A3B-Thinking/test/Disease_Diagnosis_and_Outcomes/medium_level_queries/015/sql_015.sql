WITH stroke_diagnoses AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code BETWEEN '430' AND '438') OR
    (icd_version = 10 AND icd_code BETWEEN 'I60' AND 'I69')
),
charlson_scores AS (
  SELECT 
    d.hadm_id,
    SUM(
      CASE 
        WHEN (d.icd_version = 9 AND d.icd_code = '410') OR (d.icd_version = 10 AND d.icd_code LIKE 'I21%') THEN 1
        WHEN (d.icd_version = 9 AND d.icd_code = '428') OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%') THEN 1
        WHEN (d.icd_version = 9 AND d.icd_code IN ('440', '443.9')) OR (d.icd_version = 10 AND d.icd_code IN ('I70', 'I73.9')) THEN 1
        WHEN (d.icd_version = 9 AND d.icd_code BETWEEN '430' AND '438') OR (d.icd_version = 10 AND d.icd_code BETWEEN 'I60' AND 'I69') THEN 1
        WHEN (d.icd_version = 9 AND d.icd_code BETWEEN '290' AND '294') OR (d.icd_version = 10 AND d.icd_code BETWEEN 'F01' AND 'F03') THEN 1
        WHEN (d.icd_version = 9 AND d.icd_code BETWEEN '490' AND '496') OR (d.icd_version = 10 AND d.icd_code BETWEEN 'J40' AND 'J47') THEN 1
        WHEN (d.icd_version = 9 AND d.icd_code = '710') OR (d.icd_version = 10 AND d.icd_code BETWEEN 'M05' AND 'M06') THEN 1
        WHEN (d.icd_version = 9 AND d.icd_code BETWEEN '531' AND '534') OR (d.icd_version = 10 AND d.icd_code BETWEEN 'K25' AND 'K28') THEN 1
        WHEN (d.icd_version = 9 AND d.icd_code IN ('570', '571.0', '571.1')) OR (d.icd_version = 10 AND d.icd_code IN ('K70.0', 'K70.1', 'K70.2', 'K70.3', 'K71.3', 'K71.4', 'K71.5')) THEN 1
        WHEN (d.icd_version = 9 AND d.icd_code = '250.0') OR (d.icd_version = 10 AND d.icd_code LIKE 'E11.0%') THEN 1
        WHEN (d.icd_version = 9 AND d.icd_code BETWEEN '250.1' AND '250.8') OR (d.icd_version = 10 AND (d.icd_code LIKE 'E11.1%' OR d.icd_code LIKE 'E11.2%' OR d.icd_code LIKE 'E11.3%' OR d.icd_code LIKE 'E11.4%' OR d.icd_code LIKE 'E11.5%' OR d.icd_code LIKE 'E11.6%' OR d.icd_code LIKE 'E11.7%' OR d.icd_code LIKE 'E11.8%' OR d.icd_code LIKE 'E11.9%')) THEN 2
        WHEN (d.icd_version = 9 AND d.icd_code = '344.0') OR (d.icd_version = 10 AND d.icd_code = 'G82.2') THEN 2
        WHEN (d.icd_version = 9 AND d.icd_code IN ('585', '586')) OR (d.icd_version = 10 AND d.icd_code BETWEEN 'N18' AND 'N19') THEN 2
        WHEN (d.icd_version = 9 AND d.icd_code BETWEEN '140' AND '208') OR (d.icd_version = 10 AND d.icd_code BETWEEN 'C00' AND 'C97') THEN 2
        WHEN (d.icd_version = 9 AND d.icd_code IN ('571.2', '571.3', '571.4', '571.5')) OR (d.icd_version = 10 AND d.icd_code IN ('K70.4', 'K70.5', 'K70.6', 'K70.7', 'K70.8', 'K70.9', 'K71.1', 'K71.2', 'K71.6', 'K71.7', 'K71.8', 'K71.9')) THEN 3
        WHEN (d.icd_version = 9 AND d.icd_code BETWEEN '196' AND '199') OR (d.icd_version = 10 AND d.icd_code BETWEEN 'C77' AND 'C80') THEN 6
        WHEN (d.icd_version = 9 AND d.icd_code = '042') OR (d.icd_version = 10 AND d.icd_code = 'B20') THEN 6
        ELSE 0
      END
    ) AS charlson_score
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  GROUP BY d.hadm_id
),
stroke_admissions AS (
  SELECT 
    a.hadm_id,
    a.hospital_expire_flag,
    CASE 
      WHEN i.stay_id IS NOT NULL THEN 'ICU'
      ELSE 'Non-ICU'
    END AS icu_status,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    c.charlson_score
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN stroke_diagnoses s ON a.hadm_id = s.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
  LEFT JOIN charlson_scores c ON a.hadm_id = c.hadm_id
  WHERE 
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 48 AND 58
)
SELECT 
  icu_status,
  CASE WHEN los_days <= 5 THEN 'LOS ≤5' ELSE 'LOS >5' END AS los_group,
  CASE 
    WHEN charlson_score <= 1 THEN 'Low'
    WHEN charlson_score BETWEEN 2 AND 3 THEN 'Medium'
    ELSE 'High'
  END AS charlson_category,
  AVG(hospital_expire_flag) * 100 AS mortality_rate,
  (AVG(hospital_expire_flag) - 1.96 * SQRT(AVG(hospital_expire_flag) * (1 - AVG(hospital_expire_flag)) / COUNT(*))) * 100 AS lower_ci,
  (AVG(hospital_expire_flag) + 1.96 * SQRT(AVG(hospital_expire_flag) * (1 - AVG(hospital_expire_flag)) / COUNT(*))) * 100 AS upper_ci
FROM stroke_admissions
GROUP BY icu_status, los_group, charlson_category;