WITH cohort AS (
  SELECT 
    a.hadm_id,
    p.subject_id,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 46 AND 56
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '410%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'I21.%')
        )
    )
),
complication_counts AS (
  SELECT 
    hadm_id,
    MAX(CASE WHEN (icd_version = 9 AND icd_code LIKE '428%') 
                OR (icd_version = 10 AND icd_code LIKE 'I50.%') 
             THEN 1 ELSE 0 END) AS heart_failure,
    MAX(CASE WHEN (icd_version = 9 AND icd_code = '78551') 
                OR (icd_version = 10 AND icd_code = 'R57.0') 
             THEN 1 ELSE 0 END) AS cardiogenic_shock,
    MAX(CASE WHEN (icd_version = 9 AND icd_code LIKE '4275%') 
                OR (icd_version = 10 AND icd_code LIKE 'I46.%') 
             THEN 1 ELSE 0 END) AS cardiac_arrest,
    MAX(CASE WHEN (icd_version = 9 AND icd_code = '42741') 
                OR (icd_version = 10 AND icd_code = 'I49.01') 
             THEN 1 ELSE 0 END) AS vfib,
    MAX(CASE WHEN (icd_version = 9 AND (
                   icd_code LIKE '430%' OR icd_code LIKE '431%' OR 
                   icd_code LIKE '432%' OR icd_code LIKE '433%' OR 
                   icd_code LIKE '434%' OR icd_code LIKE '436%'))
                OR (icd_version = 10 AND (
                   icd_code LIKE 'I60%' OR icd_code LIKE 'I61%' OR 
                   icd_code LIKE 'I62%' OR icd_code LIKE 'I63%' OR 
                   icd_code LIKE 'I64%'))
             THEN 1 ELSE 0 END) AS stroke
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE hadm_id IN (SELECT hadm_id FROM cohort)
  GROUP BY hadm_id
),
patient_data AS (
  SELECT 
    c.hadm_id,
    c.subject_id,
    c.age,
    c.hospital_expire_flag,
    COALESCE(comp.heart_failure, 0) + 
    COALESCE(comp.cardiogenic_shock, 0) + 
    COALESCE(comp.cardiac_arrest, 0) + 
    COALESCE(comp.vfib, 0) + 
    COALESCE(comp.stroke, 0) AS num_complications,
    c.age + (
      COALESCE(comp.heart_failure, 0) + 
      COALESCE(comp.cardiogenic_shock, 0) + 
      COALESCE(comp.cardiac_arrest, 0) + 
      COALESCE(comp.vfib, 0) + 
      COALESCE(comp.stroke, 0)
    ) AS composite_score
  FROM cohort c
  LEFT JOIN complication_counts comp
    ON c.hadm_id = comp.hadm_id
),
los_data AS (
  SELECT 
    hadm_id,
    TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  WHERE hadm_id IN (SELECT hadm_id FROM patient_data)
),
final_data AS (
  SELECT 
    pd.*,
    los.los_days
  FROM patient_data pd
  INNER JOIN los_data los
    ON pd.hadm_id = los.hadm_id
),
quintiles AS (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY composite_score) AS quintile
  FROM final_data
)
SELECT 
  quintile,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_pct,
  ROUND(AVG(CASE WHEN num_complications > 0 THEN 1 ELSE 0 END) * 100, 2) AS major_complication_pct,
  ROUND(APPROX_QUANTILES(CASE WHEN hospital_expire_flag = 0 THEN los_days END, 100)[OFFSET(50)], 2) AS median_survivor_los
FROM quintiles
GROUP BY quintile
ORDER BY quintile;