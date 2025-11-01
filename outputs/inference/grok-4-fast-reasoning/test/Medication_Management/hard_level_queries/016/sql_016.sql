WITH hepatic_hadms AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
    ON di.icd_code = dd.icd_code 
    AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%hepatic failure%'
),
cohort AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    p.gender, 
    p.anchor_age,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  JOIN hepatic_hadms hh 
    ON a.hadm_id = hh.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
),
med_scores AS (
  SELECT 
    c.*,
    COUNT(DISTINCT ph.medication) AS med_complexity_score
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.pharmacy` ph 
    ON c.hadm_id = ph.hadm_id
    AND ph.starttime >= c.admittime
    AND ph.starttime < DATETIME_ADD(c.admittime, INTERVAL 7 DAY)
  GROUP BY 
    c.subject_id, c.hadm_id, c.admittime, c.dischtime, c.hospital_expire_flag, 
    c.gender, c.anchor_age, c.los_days
),
cohort_with_tertile AS (
  SELECT *,
    NTILE(3) OVER (ORDER BY med_complexity_score ASC) AS tertile
  FROM med_scores
)
SELECT 
  tertile,
  COUNT(*) AS n_admissions,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 1.0 / COUNT(*), 4) AS mortality_rate,
  ROUND(
    SUM(CASE WHEN hospital_expire_flag = 0 AND has_30d_readmit THEN 1 ELSE 0 END) * 1.0 / 
    SUM(CASE WHEN hospital_expire_flag = 0 THEN 1 ELSE 0 END), 4
  ) AS readmit_30d_rate
FROM (
  SELECT 
    cwt.*,
    CASE 
      WHEN cwt.hospital_expire_flag = 0 THEN
        EXISTS (
          SELECT 1 
          FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
          WHERE a2.subject_id = cwt.subject_id
            AND a2.hadm_id != cwt.hadm_id
            AND a2.admittime > cwt.dischtime
            AND a2.admittime <= DATETIME_ADD(cwt.dischtime, INTERVAL 30 DAY)
        )
      ELSE FALSE 
    END AS has_30d_readmit
  FROM cohort_with_tertile cwt
)
GROUP BY tertile
ORDER BY tertile;