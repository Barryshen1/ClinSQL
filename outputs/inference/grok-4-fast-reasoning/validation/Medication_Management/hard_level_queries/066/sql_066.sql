WITH transplant_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%transplant%'
),
cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN transplant_codes t
        ON d.icd_code = t.icd_code
        AND d.icd_version = t.icd_version
      WHERE d.subject_id = a.subject_id
        AND d.hadm_id = a.hadm_id
    )
),
scores AS (
  SELECT
    c.*,
    COUNT(DISTINCT pr.drug) AS med_complexity_score,
    CASE
      WHEN c.hospital_expire_flag = 1 THEN 0
      ELSE CASE
        WHEN EXISTS (
          SELECT 1
          FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
          WHERE a2.subject_id = c.subject_id
            AND a2.hadm_id != c.hadm_id
            AND a2.admittime > c.dischtime
            AND a2.admittime < TIMESTAMP_ADD(c.dischtime, INTERVAL 30 DAY)
        ) THEN 1
        ELSE 0
      END
    END AS readmit_flag
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
    AND pr.starttime >= c.admittime
    AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 7 DAY)
  GROUP BY
    c.subject_id, c.hadm_id, c.admittime, c.dischtime, c.hospital_expire_flag,
    c.anchor_age, c.los_days
),
quartiled AS (
  SELECT *,
    NTILE(4) OVER (ORDER BY med_complexity_score ASC) AS quartile
  FROM scores
)
SELECT
  quartile,
  COUNT(*) AS n,
  AVG(med_complexity_score) AS mean_score,
  AVG(los_days) AS mean_los,
  AVG(hospital_expire_flag) AS mortality_rate,
  SAFE_DIVIDE(
    SUM(readmit_flag),
    COUNT(CASE WHEN hospital_expire_flag = 0 THEN 1 END)
  ) AS readmission_rate
FROM quartiled
GROUP BY quartile
ORDER BY quartile;