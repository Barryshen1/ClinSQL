WITH cohort AS (
  SELECT DISTINCT
    adm.subject_id,
    adm.hadm_id,
    pat.gender,
    pat.anchor_age,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON adm.subject_id = di.subject_id
   AND adm.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON di.icd_code = dicd.icd_code
   AND di.icd_version = dicd.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 43 AND 53
    AND UPPER(dicd.long_title) LIKE '%TRANSPLANT%'
),
med_complexity AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    COUNT(DISTINCT pr.drug) AS complexity_score
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.subject_id = pr.subject_id
   AND c.hadm_id = pr.hadm_id
   AND pr.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 7 DAY)
  GROUP BY c.subject_id, c.hadm_id
),
cohort_with_score AS (
  SELECT
    c.*,
    mc.complexity_score,
    DATE_DIFF(c.dischtime, c.admittime, DAY) AS los_days
  FROM cohort c
  LEFT JOIN med_complexity mc
    ON c.subject_id = mc.subject_id
   AND c.hadm_id = mc.hadm_id
),
readmit_flag AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    CASE WHEN MIN(b.admittime) IS NOT NULL THEN 1 ELSE 0 END AS readmit_30d
  FROM cohort_with_score a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` b
    ON a.subject_id = b.subject_id
   AND b.admittime > a.dischtime
   AND DATETIME_DIFF(b.admittime, a.dischtime, DAY) <= 30
  GROUP BY a.subject_id, a.hadm_id
),
with_flags AS (
  SELECT
    cws.*,
    rf.readmit_30d
  FROM cohort_with_score cws
  LEFT JOIN readmit_flag rf
    ON cws.subject_id = rf.subject_id
   AND cws.hadm_id = rf.hadm_id
),
with_quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY complexity_score) AS complexity_quartile
  FROM with_flags
)
SELECT
  complexity_quartile,
  COUNT(*) AS n_admissions,
  ROUND(AVG(complexity_score),2) AS mean_score,
  ROUND(AVG(los_days),2) AS mean_los_days,
  ROUND(AVG(hospital_expire_flag)*100,2) AS in_hosp_mortality_pct,
  ROUND(AVG(readmit_30d)*100,2) AS readmit_30d_pct
FROM with_quartiles
GROUP BY complexity_quartile
ORDER BY complexity_quartile;