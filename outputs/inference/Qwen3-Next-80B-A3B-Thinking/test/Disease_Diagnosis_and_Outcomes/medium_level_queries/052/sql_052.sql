WITH stroke_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag,
         p.gender, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
    AND (
        (d.icd_version = 9 AND d.icd_code BETWEEN '430' AND '438')
        OR (d.icd_version = 10 AND d.icd_code BETWEEN 'I60' AND 'I69')
    )
),

icu_status AS (
  SELECT a.hadm_id,
         CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS is_icu
  FROM stroke_admissions a
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
),

los AS (
  SELECT hadm_id,
         TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los
  FROM stroke_admissions
),

charlson_points AS (
  SELECT d.hadm_id,
         CASE
             WHEN (d.icd_version = 9 AND d.icd_code BETWEEN '410' AND '414') OR (d.icd_version = 10 AND d.icd_code BETWEEN 'I21' AND 'I25') THEN 1
             WHEN (d.icd_version = 9 AND d.icd_code BETWEEN '428' AND '428') OR (d.icd_version = 10 AND d.icd_code BETWEEN 'I50' AND 'I50') THEN 1
             WHEN (d.icd_version = 9 AND d.icd_code IN ('440', '443.9')) OR (d.icd_version = 10 AND d.icd_code BETWEEN 'I70' AND 'I73') THEN 1
             WHEN (d.icd_version = 9 AND d.icd_code BETWEEN '430' AND '438') OR (d.icd_version = 10 AND d.icd_code BETWEEN 'I60' AND 'I69') THEN 1
             WHEN (d.icd_version = 9 AND d.icd_code BETWEEN '290' AND '294') OR (d.icd_version = 10 AND d.icd_code BETWEEN 'F01' AND 'F03') THEN 1
             WHEN (d.icd_version = 9 AND d.icd_code BETWEEN '490' AND '496') OR (d.icd_version = 10 AND d.icd_code BETWEEN 'J40' AND 'J47') THEN 1
             WHEN (d.icd_version = 9 AND d.icd_code BETWEEN '710' AND '710') OR (d.icd_version = 10 AND d.icd_code BETWEEN 'M30' AND 'M36') THEN 1
             WHEN (d.icd_version = 9 AND d.icd_code BETWEEN '531' AND '534') OR (d.icd_version = 10 AND d.icd_code BETWEEN 'K25' AND 'K28') THEN 1
             WHEN (d.icd_version = 9 AND d.icd_code BETWEEN '570' AND '571') OR (d.icd_version = 10 AND d.icd_code BETWEEN 'K70' AND 'K77') THEN 1
             WHEN (d.icd_version = 9 AND d.icd_code LIKE '250.0%') OR (d.icd_version = 10 AND d.icd_code IN ('E11.0', 'E11.1')) THEN 1
             WHEN (d.icd_version = 9 AND (d.icd_code LIKE '250.4%' OR d.icd_code LIKE '250.6%' OR d.icd_code LIKE '250.8%' OR d.icd_code LIKE '250.9%')) OR (d.icd_version = 10 AND d.icd_code IN ('E10.4', 'E10.5', 'E11.4', 'E11.5', 'E13.4', 'E13.5')) THEN 2
             WHEN (d.icd_version = 9 AND d.icd_code BETWEEN '342' AND '344') OR (d.icd_version = 10 AND d.icd_code BETWEEN 'G81' AND 'G82') THEN 2
             WHEN (d.icd_version = 9 AND d.icd_code BETWEEN '585' AND '585') OR (d.icd_version = 10 AND d.icd_code BETWEEN 'N18' AND 'N18') THEN 2
             WHEN (d.icd_version = 9 AND d.icd_code BETWEEN '140' AND '208') OR (d.icd_version = 10 AND d.icd_code BETWEEN 'C00' AND 'C97') THEN 2
             WHEN (d.icd_version = 9 AND d.icd_code IN ('571.5', '571.6')) OR (d.icd_version = 10 AND d.icd_code IN ('K70.3', 'K71.5')) THEN 3
             WHEN (d.icd_version = 9 AND d.icd_code BETWEEN '196' AND '199') OR (d.icd_version = 10 AND d.icd_code BETWEEN 'C77' AND 'C80') THEN 6
             WHEN (d.icd_version = 9 AND d.icd_code = '042') OR (d.icd_version = 10 AND d.icd_code = 'B20') THEN 6
             ELSE 0
         END AS points
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
),

charlson_scores AS (
  SELECT 
    hadm_id,
    SUM(points) AS charlson_score,
    NTILE(3) OVER (ORDER BY SUM(points)) AS comorbidity_tertile
  FROM charlson_points
  GROUP BY hadm_id
),

ckd_diabetes AS (
  SELECT d.hadm_id,
         MAX(CASE WHEN (d.icd_version = 9 AND d.icd_code BETWEEN '585' AND '585') OR (d.icd_version = 10 AND d.icd_code BETWEEN 'N18' AND 'N18') THEN 1 ELSE 0 END) AS has_ckd,
         MAX(CASE WHEN (d.icd_version = 9 AND d.icd_code LIKE '250.%') OR (d.icd_version = 10 AND d.icd_code BETWEEN 'E08' AND 'E13') THEN 1 ELSE 0 END) AS has_diabetes
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  GROUP BY d.hadm_id
)

SELECT
  is_icu,
  CASE WHEN los <= 5 THEN '≤5' ELSE '>5' END AS los_group,
  cs.comorbidity_tertile,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_pct,
  ROUND(AVG(has_ckd) * 100, 2) AS ckd_pct,
  ROUND(AVG(has_diabetes) * 100, 2) AS diabetes_pct
FROM stroke_admissions sa
JOIN icu_status i ON sa.hadm_id = i.hadm_id
JOIN los l ON sa.hadm_id = l.hadm_id
LEFT JOIN charlson_scores cs ON sa.hadm_id = cs.hadm_id
LEFT JOIN ckd_diabetes cd ON sa.hadm_id = cd.hadm_id
GROUP BY is_icu, los_group, cs.comorbidity_tertile
ORDER BY is_icu, los_group, cs.comorbidity_tertile;