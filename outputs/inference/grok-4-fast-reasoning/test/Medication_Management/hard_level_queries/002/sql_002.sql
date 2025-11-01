WITH qualifying_adms AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag,
         p.gender, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 67 AND 77
    AND a.hadm_id IS NOT NULL
),
ami_adms AS (
  SELECT DISTINCT qa.*
  FROM qualifying_adms qa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON qa.subject_id = d.subject_id AND qa.hadm_id = d.hadm_id
  WHERE (d.icd_version = 9 AND d.icd_code LIKE '410%')
     OR (d.icd_version = 10 AND d.icd_code LIKE 'I21%')
),
med_scores AS (
  SELECT a.*,
         COUNT(DISTINCT pres.drug) AS med_complexity_score
  FROM ami_adms a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
    ON a.subject_id = pres.subject_id
    AND a.hadm_id = pres.hadm_id
    AND pres.drug IS NOT NULL
    AND pres.starttime >= a.admittime
    AND pres.starttime < TIMESTAMP_ADD(a.admittime, INTERVAL 1 DAY)
  GROUP BY a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag,
           a.gender, a.anchor_age
),
all_adms_for_subjects AS (
  SELECT subject_id, hadm_id, admittime, dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  WHERE subject_id IN (SELECT DISTINCT subject_id FROM med_scores)
),
readmit_flags AS (
  SELECT ms.*,
         EXISTS (
           SELECT 1
           FROM all_adms_for_subjects ra
           WHERE ra.subject_id = ms.subject_id
             AND ra.hadm_id != ms.hadm_id
             AND ra.admittime > ms.dischtime
             AND ra.admittime <= TIMESTAMP_ADD(ms.dischtime, INTERVAL 30 DAY)
         ) AS has_readmit
  FROM med_scores ms
),
ranked_adms AS (
  SELECT *,
         TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0 AS los_days,
         NTILE(3) OVER (ORDER BY med_complexity_score ASC) AS tertile
  FROM readmit_flags
  WHERE dischtime IS NOT NULL  -- Exclude incomplete admissions
)
SELECT 
  tertile,
  COUNT(*) AS admission_count,
  MIN(med_complexity_score) AS score_min,
  MAX(med_complexity_score) AS score_max,
  ROUND(AVG(med_complexity_score), 2) AS score_mean,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(100.0 * AVG(hospital_expire_flag), 2) AS mortality_pct,
  ROUND(100.0 * 
    SUM(CASE WHEN hospital_expire_flag = 0 AND has_readmit THEN 1.0 ELSE 0 END) / 
    NULLIF(SUM(CASE WHEN hospital_expire_flag = 0 THEN 1.0 ELSE 0 END), 0), 
    2
  ) AS readmit_30d_pct
FROM ranked_adms
GROUP BY tertile
ORDER BY tertile;