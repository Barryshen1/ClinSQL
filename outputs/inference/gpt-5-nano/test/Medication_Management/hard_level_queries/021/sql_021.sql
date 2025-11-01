WITH base_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE (p.gender = 'Male' OR p.gender = 'M')
    AND p.anchor_age BETWEEN 41 AND 51
),

-- Neutropenia diagnoses
neutropenia_adms AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%neutropenia%'
),

-- Fever diagnoses
fever_adms AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%fever%'
),

-- Admissions that have both neutropenia and fever
cohort_neutro_fever AS (
  SELECT bc.subject_id, bc.hadm_id, bc.admittime, bc.dischtime, bc.hospital_expire_flag
  FROM base_cohort AS bc
  JOIN neutropenia_adms AS n ON bc.subject_id = n.subject_id AND bc.hadm_id = n.hadm_id
  JOIN fever_adms AS f ON bc.subject_id = f.subject_id AND bc.hadm_id = f.hadm_id
),

-- Medications count in first 48 hours
meds_within_48h AS (
  SELECT cn.subject_id,
         cn.hadm_id,
         cn.admittime,
         cn.dischtime,
         cn.hospital_expire_flag,
         COUNT(DISTINCT pr.drug) AS med_count
  FROM cohort_neutro_fever AS cn
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON pr.subject_id = cn.subject_id
   AND pr.hadm_id = cn.hadm_id
   AND pr.starttime >= cn.admittime
   AND pr.starttime < TIMESTAMP_ADD(cn.admittime, INTERVAL 48 HOUR)
  GROUP BY cn.subject_id, cn.hadm_id, cn.admittime, cn.dischtime, cn.hospital_expire_flag
),

-- 30-day readmission flag
readmission_flag AS (
  SELECT mw48.subject_id,
         mw48.hadm_id,
         mw48.admittime,
         mw48.dischtime,
         mw48.hospital_expire_flag,
         mw48.med_count,
         TIMESTAMP_DIFF(mw48.dischtime, mw48.admittime, SECOND) / 86400.0 AS los_days,
         CASE
           WHEN EXISTS (
             SELECT 1
             FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
             WHERE a2.subject_id = mw48.subject_id
               AND a2.admittime > mw48.dischtime
               AND a2.admittime <= TIMESTAMP_ADD(mw48.dischtime, INTERVAL 30 DAY)
           ) THEN 1
           ELSE 0
         END AS readmit_30_flag
  FROM meds_within_48h AS mw48
)

SELECT
  tertile AS tertile,
  AVG(los_days) AS avg_los_days,
  100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS in_hosp_mortality_pct,
  100.0 * SUM(readmit_30_flag) / COUNT(*) AS readmission_30d_pct
FROM (
  -- Assign tertiles based on med_count
  SELECT subject_id,
         hadm_id,
         admittime,
         dischtime,
         hospital_expire_flag,
         med_count,
         los_days,
         readmit_30_flag,
         NTILE(3) OVER (ORDER BY med_count) AS tertile
  FROM readmission_flag
) AS t
GROUP BY tertile
ORDER BY tertile;