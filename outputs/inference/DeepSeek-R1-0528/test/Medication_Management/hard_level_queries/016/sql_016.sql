WITH cohort AS (
  SELECT DISTINCT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    DATE(CAST(p.anchor_year - p.anchor_age AS INT64), 1, 1) AS birth_date
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  INNER JOIN (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
      ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
    WHERE d.long_title LIKE '%hepatic failure%'
  ) hf ON adm.hadm_id = hf.hadm_id
  WHERE
    p.gender = 'F'
    AND DATE_DIFF(adm.admittime, DATE(CAST(p.anchor_year - p.anchor_age AS INT64), 1, 1), YEAR) BETWEEN 80 AND 90
),

med_score AS (
  SELECT
    c.hadm_id,
    COUNT(DISTINCT pr.drug) AS score
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
    AND pr.starttime <= DATETIME_ADD(c.admittime, INTERVAL 7 DAY)
    AND (pr.stoptime >= c.admittime OR pr.stoptime IS NULL)
  GROUP BY c.hadm_id
),

cohort_with_tertile AS (
  SELECT
    c.*,
    COALESCE(m.score, 0) AS med_complexity_score,
    NTILE(3) OVER (ORDER BY COALESCE(m.score, 0)) AS tertile
  FROM cohort c
  LEFT JOIN med_score m ON c.hadm_id = m.hadm_id
),

readmission_flag AS (
  SELECT
    c.hadm_id,
    CASE
      WHEN c.hospital_expire_flag = 1 THEN 0  -- Deceased patients cannot be readmitted
      WHEN nxt.hadm_id IS NOT NULL THEN 1
      ELSE 0
    END AS readmit_30d
  FROM cohort_with_tertile c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` nxt
    ON c.subject_id = nxt.subject_id
    AND nxt.admittime > c.dischtime
    AND nxt.admittime <= DATETIME_ADD(c.dischtime, INTERVAL 30 DAY)
)

SELECT
  tertile,
  COUNT(*) AS num_admissions,
  AVG(DATETIME_DIFF(dischtime, admittime, DAY)) AS avg_los_days,
  AVG(hospital_expire_flag) AS mortality_rate,
  AVG(readmit_30d) AS readmission_rate
FROM cohort_with_tertile c
INNER JOIN readmission_flag r ON c.hadm_id = r.hadm_id
GROUP BY tertile
ORDER BY tertile;