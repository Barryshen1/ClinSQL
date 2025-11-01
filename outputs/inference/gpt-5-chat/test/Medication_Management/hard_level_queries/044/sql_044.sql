WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 64 AND 74
    AND (
         (d.icd_version = 9 AND d.icd_code LIKE '4151%')
         OR (d.icd_version = 10 AND d.icd_code LIKE 'I26%')
        )
),
med_counts AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    COUNT(DISTINCT e.medication) AS med_count,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
    ON c.subject_id = e.subject_id
    AND c.hadm_id = e.hadm_id
    AND e.charttime >= c.admittime
    AND e.charttime < DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
  GROUP BY c.subject_id, c.hadm_id, c.admittime, c.dischtime, c.hospital_expire_flag
),
with_tertile AS (
  SELECT
    m.*,
    NTILE(3) OVER (ORDER BY med_count) AS tertile
  FROM med_counts m
),
tertile_ranges AS (
  SELECT
    tertile,
    MIN(med_count) AS min_med_count,
    MAX(med_count) AS max_med_count
  FROM with_tertile
  GROUP BY tertile
),
readmission_flags AS (
  SELECT
    w.subject_id,
    w.hadm_id,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = w.subject_id
          AND a2.admittime > w.dischtime
          AND a2.admittime <= DATETIME_ADD(w.dischtime, INTERVAL 30 DAY)
      ) THEN 1 ELSE 0
    END AS readmit_30d
  FROM with_tertile w
)
SELECT
  w.tertile,
  r.min_med_count,
  r.max_med_count,
  COUNT(*) AS admissions,
  ROUND(AVG(TIMESTAMP_DIFF(w.dischtime, w.admittime, HOUR) / 24.0), 2) AS avg_los_days,
  ROUND(100 * AVG(w.hospital_expire_flag), 1) AS mortality_pct,
  ROUND(100 * AVG(f.readmit_30d), 1) AS readmit_30d_pct
FROM with_tertile w
JOIN tertile_ranges r
  ON w.tertile = r.tertile
JOIN readmission_flags f
  ON w.subject_id = f.subject_id AND w.hadm_id = f.hadm_id
GROUP BY w.tertile, r.min_med_count, r.max_med_count
ORDER BY w.tertile;