WITH cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 71 AND 81
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = '9' AND d.icd_code LIKE '577.0%')
          OR
          (d.icd_version = '10' AND d.icd_code LIKE 'K85%')
        )
    )
),
med_complexity AS (
  SELECT
    c.*,
    COUNT(DISTINCT e.medication) AS med_score
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
    ON c.subject_id = e.subject_id
    AND c.hadm_id = e.hadm_id
    AND e.charttime >= c.admittime
    AND e.charttime < TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
    AND e.medication IS NOT NULL
  GROUP BY
    c.subject_id, c.hadm_id, c.admittime, c.dischtime,
    c.hospital_expire_flag, c.anchor_age, c.gender
),
analysis AS (
  SELECT
    m.*,
    CASE
      WHEN m.hospital_expire_flag = 0 THEN
        CASE
          WHEN EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
            WHERE a2.subject_id = m.subject_id
              AND a2.hadm_id != m.hadm_id
              AND a2.admittime > m.dischtime
              AND a2.admittime <= TIMESTAMP_ADD(m.dischtime, INTERVAL 30 DAY)
          ) THEN 1
          ELSE 0
        END
      ELSE NULL
    END AS readmitted
  FROM med_complexity m
),
tertiles AS (
  SELECT
    *,
    NTILE(3) OVER (ORDER BY med_score ASC) AS tertile
  FROM analysis
)
SELECT
  tertile,
  COUNT(*) AS n_admissions,
  ROUND(AVG(DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0), 2) AS mean_los_days,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_pct,
  ROUND(AVG(readmitted) * 100, 2) AS readmission_30d_pct
FROM tertiles
GROUP BY tertile
ORDER BY tertile;