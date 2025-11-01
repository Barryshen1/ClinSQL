WITH ich_patients AS (
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
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.hadm_id = dx.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON dx.icd_code = dd.icd_code
    AND dx.icd_version = dd.icd_version
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 87 AND 97
    AND LOWER(dd.long_title) LIKE '%hemorrhage%'
    AND LOWER(dd.long_title) LIKE '%intracranial%'
),
drug_complexity AS (
  SELECT
    p.hadm_id,
    COUNT(DISTINCT CONCAT(IFNULL(pr.drug,''), '||', IFNULL(pr.route,''))) AS complexity_score
  FROM ich_patients p
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON p.hadm_id = pr.hadm_id
  WHERE pr.starttime >= p.admittime
    AND pr.starttime < DATETIME_ADD(p.admittime, INTERVAL 48 HOUR)
  GROUP BY p.hadm_id
),
cohort AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.gender,
    p.anchor_age,
    p.admittime,
    p.dischtime,
    p.hospital_expire_flag,
    dc.complexity_score,
    DATETIME_DIFF(p.dischtime, p.admittime, MINUTE)/1440.0 AS los_days
  FROM ich_patients p
  LEFT JOIN drug_complexity dc
    ON p.hadm_id = dc.hadm_id
),
quartiles AS (
  SELECT
    c.*,
    NTILE(4) OVER (ORDER BY complexity_score) AS complexity_quartile
  FROM cohort c
),
readmit_flags AS (
  SELECT
    q.subject_id,
    q.hadm_id,
    MIN(adm2.admittime) AS next_admit
  FROM quartiles q
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm2
    ON q.subject_id = adm2.subject_id
    AND q.hadm_id != adm2.hadm_id
    AND adm2.admittime > q.dischtime
    AND adm2.admittime <= DATETIME_ADD(q.dischtime, INTERVAL 30 DAY)
  GROUP BY q.subject_id, q.hadm_id
),
quartile_stats AS (
  SELECT
    q.complexity_quartile,
    MIN(q.complexity_score) AS complexity_min,
    MAX(q.complexity_score) AS complexity_max,
    COUNT(*) AS admissions,
    AVG(q.los_days) AS avg_los,
    100.0 * SUM(CASE WHEN q.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS mortality_pct,
    100.0 * SUM(CASE WHEN rf.next_admit IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*) AS readmit_30d_pct
  FROM quartiles q
  LEFT JOIN readmit_flags rf
    ON q.hadm_id = rf.hadm_id
  GROUP BY q.complexity_quartile
  ORDER BY q.complexity_quartile
)
SELECT *
FROM quartile_stats;