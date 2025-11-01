WITH eligible_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
    -- LOS between 1 and 8 days (inclusive)
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 8
    -- Has at least one diagnosis indicative of upper GI bleeding
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
        AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND (
          LOWER(dd.long_title) LIKE '%gastrointestinal hemorrhag%'
          OR LOWER(dd.long_title) LIKE '%upper gastrointestinal%'
          OR LOWER(dd.long_title) LIKE '%hematemesis%'
          OR LOWER(dd.long_title) LIKE '%melena%'
        )
    )
),

per_admission_diag_counts AS (
  SELECT
    e.hadm_id,
    e.los_days,
    COUNT(DISTINCT CASE
      WHEN dp.long_title IS NOT NULL
        AND (
          LOWER(dp.long_title) LIKE '%diagnos%'
          OR LOWER(dp.long_title) LIKE '%endoscop%'
          OR LOWER(dp.long_title) LIKE '%esophag%'
          OR LOWER(dp.long_title) LIKE '%gastroduoden%'
          OR LOWER(dp.long_title) LIKE '%angiograph%'
        )
      THEN CONCAT(COALESCE(CAST(pr.chartdate AS STRING), ''), '|', COALESCE(pr.icd_code, ''), '|', CAST(pr.seq_num AS STRING))
      ELSE NULL END
    ) AS diag_proc_count
  FROM eligible_admissions e
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON pr.hadm_id = e.hadm_id
       AND (
         pr.chartdate IS NULL
         OR (pr.chartdate BETWEEN DATE(e.admittime) AND DATE(e.dischtime))
       )
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON pr.icd_code = dp.icd_code
       AND pr.icd_version = dp.icd_version
  GROUP BY e.hadm_id, e.los_days
)

SELECT
  bin,
  q[OFFSET(1)] AS p25_diag_procs_per_admission,
  q[OFFSET(2)] AS p50_diag_procs_per_admission,
  q[OFFSET(3)] AS p75_diag_procs_per_admission
FROM (
  SELECT
    bin,
    APPROX_QUANTILES(diag_proc_count, 4) AS q
  FROM (
    SELECT
      hadm_id,
      diag_proc_count,
      CASE
        WHEN los_days BETWEEN 1 AND 4 THEN '1-4'
        WHEN los_days BETWEEN 5 AND 8 THEN '5-8'
        ELSE NULL
      END AS bin
    FROM per_admission_diag_counts
  )
  WHERE bin IS NOT NULL
  GROUP BY bin
)
ORDER BY bin;