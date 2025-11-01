WITH hepatic_dx AS (
  -- identify admissions with hepatic / liver failure diagnoses
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE (
      LOWER(COALESCE(dicd.long_title, '')) LIKE '%hepatic%'
      OR LOWER(COALESCE(dicd.long_title, '')) LIKE '%liver failure%'
    )
),

cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN hepatic_dx h
    ON a.hadm_id = h.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
),

meds_7d AS (
  -- medication identities (coalesced) prescribed/active in first 7 days of admission
  SELECT
    pr.hadm_id,
    LOWER(TRIM(COALESCE(pr.drug, pr.formulary_drug_cd, pr.ndc))) AS med_id
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN cohort c
    ON pr.hadm_id = c.hadm_id
  WHERE
    pr.starttime IS NOT NULL
    -- overlap with [admittime, admittime + 7 days]
    AND pr.starttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 7 DAY)
    AND (pr.stoptime IS NULL OR pr.stoptime >= c.admittime)
    AND LOWER(COALESCE(pr.drug, pr.formulary_drug_cd, pr.ndc)) <> ''
),

med_complexity AS (
  -- count distinct meds per admission in the first 7 days
  SELECT
    c.hadm_id,
    c.subject_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    c.anchor_age,
    COALESCE(m.med_count, 0) AS med_complexity_score
  FROM cohort c
  LEFT JOIN (
    SELECT hadm_id, COUNT(DISTINCT med_id) AS med_count
    FROM meds_7d
    GROUP BY hadm_id
  ) m
  ON c.hadm_id = m.hadm_id
),

with_tertile AS (
  -- assign tertiles across admissions by med_complexity_score
  SELECT
    *,
    NTILE(3) OVER (ORDER BY med_complexity_score, hadm_id) AS tertile
  FROM med_complexity
),

readmit_flag AS (
  -- compute 30-day readmission flag per index admission
  SELECT
    w.*,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = w.subject_id
        AND a2.hadm_id <> w.hadm_id
        AND a2.admittime > w.dischtime
        AND a2.admittime <= TIMESTAMP_ADD(w.dischtime, INTERVAL 30 DAY)
    ) THEN 1 ELSE 0 END AS readmit30
  FROM with_tertile w
)

-- Final aggregation by tertile
SELECT
  tertile,
  COUNT(*) AS n_admissions,
  ROUND(AVG(med_complexity_score), 2) AS avg_med_complexity_score,
  ROUND(AVG(TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0), 2) AS mean_los_days,
  ROUND(100.0 * SUM(CAST(hospital_expire_flag AS INT64)) / COUNT(*), 2) AS in_hospital_mortality_pct,
  ROUND(100.0 * SUM(CAST(readmit30 AS INT64)) / COUNT(*), 2) AS readmit30_pct
FROM readmit_flag
GROUP BY tertile
ORDER BY tertile;