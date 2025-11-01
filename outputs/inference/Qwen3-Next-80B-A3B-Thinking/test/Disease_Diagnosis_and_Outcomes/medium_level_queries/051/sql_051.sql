WITH patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 51 AND 61
),
admissions_with_surgery AS (
  SELECT a.hadm_id, a.subject_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  WHERE a.subject_id IN (SELECT subject_id FROM patients)
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p 
      WHERE p.hadm_id = a.hadm_id
    )
),
icu_status AS (
  SELECT 
    a.hadm_id,
    CASE WHEN i.stay_id IS NOT NULL THEN 'ICU' ELSE 'Non-ICU' END AS icu_group
  FROM admissions_with_surgery a
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
),
los_calc AS (
  SELECT 
    a.hadm_id,
    EXTRACT(DAY FROM (a.dischtime - a.admittime)) AS los_days
  FROM admissions_with_surgery a
),
charlson AS (
  SELECT 
    d.hadm_id,
    COALESCE(SUM(
      CASE 
        WHEN (d.icd_version = 9 AND d.icd_code LIKE '410%') OR (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%')) THEN 1
        WHEN (d.icd_version = 9 AND d.icd_code LIKE '428%') OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%') THEN 1
        WHEN (d.icd_version = 9 AND (d.icd_code LIKE '440%' OR d.icd_code = '443.9')) OR (d.icd_version = 10 AND (d.icd_code LIKE 'I70%' OR d.icd_code LIKE 'I73.9%')) THEN 1
        WHEN (d.icd_version = 9 AND d.icd_code BETWEEN '430' AND '438') OR (d.icd_version = 10 AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%' OR d.icd_code LIKE 'I63%' OR d.icd_code LIKE 'I64%' OR d.icd_code LIKE 'I65%' OR d.icd_code LIKE 'I66%' OR d.icd_code LIKE 'I67%' OR d.icd_code LIKE 'I68%' OR d.icd_code LIKE 'I69%')) THEN 1
        WHEN (d.icd_version = 9 AND (d.icd_code LIKE '290%' OR d.icd_code = '294.1')) OR (d.icd_version = 10 AND (d.icd_code LIKE 'F01%' OR d.icd_code LIKE 'F02%' OR d.icd_code LIKE 'F03%' OR d.icd_code LIKE 'F05.1%')) THEN 1
        WHEN (d.icd_version = 9 AND d.icd_code BETWEEN '490' AND '496') OR (d.icd_version = 10 AND (d.icd_code LIKE 'J40%' OR d.icd_code LIKE 'J41%' OR d.icd_code LIKE 'J42%' OR d.icd_code LIKE 'J43%' OR d.icd_code LIKE 'J44%' OR d.icd_code LIKE 'J45%' OR d.icd_code LIKE 'J46%' OR d.icd_code LIKE 'J47%')) THEN 1
        WHEN (d.icd_version = 9 AND d.icd_code LIKE '710%') OR (d.icd_version = 10 AND (d.icd_code LIKE 'M05%' OR d.icd_code LIKE 'M06%' OR d.icd_code LIKE 'M30%' OR d.icd_code LIKE 'M31%' OR d.icd_code LIKE 'M32%' OR d.icd_code LIKE 'M33%' OR d.icd_code LIKE 'M34%' OR d.icd_code LIKE 'M35%' OR d.icd_code LIKE 'M36%')) THEN 1
        WHEN (d.icd_version = 9 AND d.icd_code BETWEEN '531' AND '534') OR (d.icd_version = 10 AND (d.icd_code LIKE 'K25%' OR d.icd_code LIKE 'K26%' OR d.icd_code LIKE 'K27%' OR d.icd_code LIKE 'K28%')) THEN 1
        WHEN (d.icd_version = 9 AND d.icd_code BETWEEN '570' AND '573') OR (d.icd_version = 10 AND (d.icd_code LIKE 'K70%' OR d.icd_code LIKE 'K71%' OR d.icd_code LIKE 'K72%' OR d.icd_code LIKE 'K73%' OR d.icd_code LIKE 'K74%' OR d.icd_code LIKE 'K75%' OR d.icd_code LIKE 'K76%' OR d.icd_code LIKE 'K77%')) THEN 1
        WHEN (d.icd_version = 9 AND d.icd_code LIKE '250%') OR (d.icd_version = 10 AND (d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E13%' OR d.icd_code LIKE 'E14%')) THEN 1
        WHEN (d.icd_version = 9 AND (d.icd_code LIKE '250.4%' OR d.icd_code LIKE '250.6%' OR d.icd_code LIKE '250.8%' OR d.icd_code LIKE '250.9%')) OR (d.icd_version = 10 AND (d.icd_code LIKE 'E10.4%' OR d.icd_code LIKE 'E10.5%' OR d.icd_code LIKE 'E10.6%' OR d.icd_code LIKE 'E10.7%' OR d.icd_code LIKE 'E11.4%' OR d.icd_code LIKE 'E11.5%' OR d.icd_code LIKE 'E11.6%' OR d.icd_code LIKE 'E11.7%' OR d.icd_code LIKE 'E13.4%' OR d.icd_code LIKE 'E13.5%' OR d.icd_code LIKE 'E13.6%' OR d.icd_code LIKE 'E13.7%' OR d.icd_code LIKE 'E14.4%' OR d.icd_code LIKE 'E14.5%' OR d.icd_code LIKE 'E14.6%' OR d.icd_code LIKE 'E14.7%')) THEN 2
        WHEN (d.icd_version = 9 AND (d.icd_code LIKE '342%' OR d.icd_code = '344.0')) OR (d.icd_version = 10 AND (d.icd_code LIKE 'G81%' OR d.icd_code LIKE 'G82%' OR d.icd_code LIKE 'G04.1%' OR d.icd_code LIKE 'G11.4%' OR d.icd_code LIKE 'G25.8%' OR d.icd_code LIKE 'G35%' OR d.icd_code LIKE 'G37.0%' OR d.icd_code LIKE 'G37.1%' OR d.icd_code LIKE 'G37.2%' OR d.icd_code LIKE 'G37.3%' OR d.icd_code LIKE 'G37.4%' OR d.icd_code LIKE 'G37.5%' OR d.icd_code LIKE 'G37.6%' OR d.icd_code LIKE 'G37.7%' OR d.icd_code LIKE 'G37.8%' OR d.icd_code LIKE 'G37.9%')) THEN 2
        WHEN (d.icd_version = 9 AND (d.icd_code LIKE '585%' OR d.icd_code = '586')) OR (d.icd_version = 10 AND (d.icd_code LIKE 'N18%' OR d.icd_code = 'N19')) THEN 2
        WHEN (d.icd_version = 9 AND (d.icd_code BETWEEN '140' AND '172' OR d.icd_code BETWEEN '174' AND '176' OR d.icd_code BETWEEN '179' AND '195' OR d.icd_code BETWEEN '200' AND '208')) OR (d.icd_version = 10 AND d.icd_code LIKE 'C%') THEN 2
        WHEN (d.icd_version = 9 AND d.icd_code BETWEEN '196' AND '199') OR (d.icd_version = 10 AND (d.icd_code LIKE 'C77%' OR d.icd_code LIKE 'C78%' OR d.icd_code LIKE 'C79%' OR d.icd_code LIKE 'C80%')) THEN 6
        WHEN (d.icd_version = 9 AND d.icd_code = '042') OR (d.icd_version = 10 AND d.icd_code = 'B20') THEN 6
        ELSE 0
      END
    ), 0) AS charlson_score
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN admissions_with_surgery a ON d.hadm_id = a.hadm_id
  GROUP BY d.hadm_id
),
ckd_diabetes AS (
  SELECT 
    d.hadm_id,
    MAX(CASE 
      WHEN (d.icd_version = 9 AND (d.icd_code LIKE '585%' OR d.icd_code = '586')) OR (d.icd_version = 10 AND (d.icd_code LIKE 'N18%' OR d.icd_code = 'N19')) THEN 1
      ELSE 0
    END) AS has_ckd,
    MAX(CASE 
      WHEN (d.icd_version = 9 AND d.icd_code LIKE '250%') OR (d.icd_version = 10 AND (d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E13%' OR d.icd_code LIKE 'E14%')) THEN 1
      ELSE 0
    END) AS has_diabetes
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN admissions_with_surgery a ON d.hadm_id = a.hadm_id
  GROUP BY d.hadm_id
)
SELECT 
  i.icu_group,
  CASE 
    WHEN l.los_days BETWEEN 1 AND 2 THEN '1-2'
    WHEN l.los_days BETWEEN 3 AND 5 THEN '3-5'
    WHEN l.los_days BETWEEN 6 AND 9 THEN '6-9'
    ELSE '>=10'
  END AS los_group,
  CASE 
    WHEN c.charlson_score <= 1 THEN '0-1'
    WHEN c.charlson_score = 2 THEN '2'
    ELSE '>=3'
  END AS charlson_group,
  AVG(a.hospital_expire_flag) * 100 AS mortality_rate,
  MEDIAN(l.los_days) AS median_los,
  AVG(cd.has_ckd) * 100 AS ckd_prevalence,
  AVG(cd.has_diabetes) * 100 AS diabetes_prevalence
FROM admissions_with_surgery a
JOIN icu_status i ON a.hadm_id = i.hadm_id
JOIN los_calc l ON a.hadm_id = l.hadm_id
LEFT JOIN charlson c ON a.hadm_id = c.hadm_id
LEFT JOIN ckd_diabetes cd ON a.hadm_id = cd.hadm_id
GROUP BY i.icu_group, los_group, charlson_group
ORDER BY i.icu_group, los_group, charlson_group;