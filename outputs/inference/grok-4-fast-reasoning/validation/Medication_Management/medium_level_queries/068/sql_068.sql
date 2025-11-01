WITH cohort AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 83 AND 93
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = a.subject_id
        AND d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND d.icd_code LIKE 'E11%')
          OR
          (d.icd_version = 9 AND (d.icd_code LIKE '250.0%' OR d.icd_code LIKE '250.2%'))
        )
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = a.subject_id
        AND d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
          OR
          (d.icd_version = 9 AND d.icd_code LIKE '428%')
        )
    )
),
insulin_pharm AS (
  SELECT
    ph.subject_id,
    ph.hadm_id,
    ph.starttime,
    CASE
      WHEN LOWER(ph.medication) LIKE '%glargine%'
        OR LOWER(ph.medication) LIKE '%detemir%'
        OR LOWER(ph.medication) LIKE '%nph%'
        OR LOWER(ph.medication) LIKE '%isophane%'
        OR LOWER(ph.medication) LIKE '%degludec%'
      THEN 1 ELSE 0
    END AS is_basal,
    CASE
      WHEN LOWER(ph.medication) LIKE '%aspart%'
        OR LOWER(ph.medication) LIKE '%lispro%'
        OR LOWER(ph.medication) LIKE '%glulisine%'
        OR LOWER(ph.medication) LIKE '%fiasp%'
        OR (LOWER(ph.medication) LIKE '%regular%'
            AND (ph.sliding_scale IS NULL OR TRIM(ph.sliding_scale) = ''))
      THEN 1 ELSE 0
    END AS is_bolus,
    CASE
      WHEN ph.sliding_scale IS NOT NULL AND TRIM(ph.sliding_scale) != ''
      THEN 1 ELSE 0
    END AS is_sliding
  FROM `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
  INNER JOIN cohort c
    ON ph.subject_id = c.subject_id AND ph.hadm_id = c.hadm_id
  WHERE LOWER(ph.medication) LIKE '%insulin%'
    AND ph.status = 'Allow'
    AND ph.starttime IS NOT NULL
),
first48_flags AS (
  SELECT
    ip.hadm_id,
    MAX(ip.is_basal) AS has_basal_first,
    MAX(ip.is_bolus) AS has_bolus_first,
    MAX(ip.is_sliding) AS has_sliding_first
  FROM insulin_pharm ip
  INNER JOIN cohort c
    ON ip.hadm_id = c.hadm_id
  WHERE ip.starttime >= c.admittime
    AND ip.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
  GROUP BY ip.hadm_id
),
final12_flags AS (
  SELECT
    ip.hadm_id,
    MAX(ip.is_basal) AS has_basal_final,
    MAX(ip.is_bolus) AS has_bolus_final,
    MAX(ip.is_sliding) AS has_sliding_final
  FROM insulin_pharm ip
  INNER JOIN cohort c
    ON ip.hadm_id = c.hadm_id
  WHERE ip.starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR)
    AND ip.starttime < c.dischtime
  GROUP BY ip.hadm_id
),
first_counts AS (
  SELECT
    CASE
      WHEN has_basal_f = 1 AND has_bolus_f = 1 THEN 'basal-bolus'
      WHEN has_basal_f = 1 THEN 'basal'
      WHEN has_bolus_f = 1 THEN 'bolus'
      WHEN has_sliding_f = 1 THEN 'sliding-scale'
      ELSE 'none'
    END AS category,
    COUNT(*) AS n_first
  FROM (
    SELECT
      c.hadm_id,
      COALESCE(f.has_basal_first, 0) AS has_basal_f,
      COALESCE(f.has_bolus_first, 0) AS has_bolus_f,
      COALESCE(f.has_sliding_first, 0) AS has_sliding_f
    FROM cohort c
    LEFT JOIN first48_flags f
      ON c.hadm_id = f.hadm_id
  )
  GROUP BY category
),
final_counts AS (
  SELECT
    CASE
      WHEN has_basal_l = 1 AND has_bolus_l = 1 THEN 'basal-bolus'
      WHEN has_basal_l = 1 THEN 'basal'
      WHEN has_bolus_l = 1 THEN 'bolus'
      WHEN has_sliding_l = 1 THEN 'sliding-scale'
      ELSE 'none'
    END AS category,
    COUNT(*) AS n_final
  FROM (
    SELECT
      c.hadm_id,
      COALESCE(l.has_basal_final, 0) AS has_basal_l,
      COALESCE(l.has_bolus_final, 0) AS has_bolus_l,
      COALESCE(l.has_sliding_final, 0) AS has_sliding_l
    FROM cohort c
    LEFT JOIN final12_flags l
      ON c.hadm_id = l.hadm_id
  )
  GROUP BY category
),
total_n AS (
  SELECT COUNT(*) AS total FROM cohort
)
SELECT
  COALESCE(f.category, l.category) AS category,
  ROUND(COALESCE(f.n_first, 0) * 100.0 / t.total, 2) AS pct_first_48h,
  ROUND(COALESCE(l.n_final, 0) * 100.0 / t.total, 2) AS pct_final_12h,
  ROUND(
    (COALESCE(f.n_first, 0) * 100.0 / t.total) - (COALESCE(l.n_final, 0) * 100.0 / t.total),
    2
  ) AS net_change
FROM first_counts f
FULL OUTER JOIN final_counts l
  ON f.category = l.category
CROSS JOIN total_n t
WHERE COALESCE(f.category, l.category) != 'none'
ORDER BY
  CASE COALESCE(f.category, l.category)
    WHEN 'basal' THEN 1
    WHEN 'bolus' THEN 2
    WHEN 'basal-bolus' THEN 3
    WHEN 'sliding-scale' THEN 4
  END;