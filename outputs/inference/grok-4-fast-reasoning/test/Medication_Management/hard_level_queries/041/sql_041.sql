WITH cohort_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 40 AND 50
),
hf_admissions AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  JOIN cohort_patients USING (subject_id)
  WHERE ((icd_version = 9 AND icd_code LIKE '428%') OR
         (icd_version = 10 AND icd_code LIKE 'I50%'))
),
admissions_data AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN hf_admissions ha USING (hadm_id)
  WHERE a.dischtime IS NOT NULL
),
med_scores AS (
  SELECT 
    ad.subject_id,
    ad.hadm_id,
    ad.admittime,
    COUNT(DISTINCT pres.drug) AS med_complexity_score
  FROM admissions_data ad
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
    ON pres.subject_id = ad.subject_id
    AND pres.hadm_id = ad.hadm_id
    AND pres.starttime >= ad.admittime
    AND (pres.starttime < TIMESTAMP_ADD(ad.admittime, INTERVAL 7 DAY) OR pres.stoptime > ad.admittime)
    AND pres.drug IS NOT NULL
    AND TRIM(pres.drug) != ''
  GROUP BY ad.subject_id, ad.hadm_id, ad.admittime
),
scored_admissions AS (
  SELECT 
    ms.subject_id,
    ms.hadm_id,
    ms.med_complexity_score,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    a.hospital_expire_flag
  FROM med_scores ms
  JOIN admissions_data a USING (subject_id, hadm_id)
),
quintiled AS (
  SELECT *,
    NTILE(5) OVER (ORDER BY med_complexity_score) AS quintile
  FROM scored_admissions
),
all_admissions_for_cohort AS (
  SELECT subject_id, hadm_id, admittime, dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  JOIN cohort_patients USING (subject_id)
  WHERE dischtime IS NOT NULL
),
readmission_flags AS (
  SELECT 
    q.*,
    CASE 
      WHEN EXISTS (
        SELECT 1
        FROM all_admissions_for_cohort ad2
        WHERE ad2.subject_id = q.subject_id
          AND ad2.hadm_id != q.hadm_id
          AND ad2.admittime > q.dischtime
          AND ad2.admittime <= TIMESTAMP_ADD(q.dischtime, INTERVAL 30 DAY)
      ) THEN 1 
      ELSE 0 
    END AS readmitted_30d
  FROM quintiled q
)
SELECT 
  quintile,
  COUNT(DISTINCT subject_id) AS patient_counts,
  MIN(med_complexity_score) AS min_score,
  MAX(med_complexity_score) AS max_score,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS in_hospital_mortality_pct,
  ROUND(AVG(readmitted_30d) * 100, 2) AS readmission_30d_pct
FROM readmission_flags
GROUP BY quintile
ORDER BY quintile;