with eligible as (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 79 AND 89
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
        ON di.icd_code = dd.icd_code
       AND di.icd_version = dd.icd_version
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%type 2 diabetes%'
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di2
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd2
        ON di2.icd_code = dd2.icd_code
       AND di2.icd_version = dd2.icd_version
      WHERE di2.subject_id = a.subject_id
        AND di2.hadm_id = a.hadm_id
        AND LOWER(dd2.long_title) LIKE '%heart failure%'
    )
)

SELECT
  eligible_count,
  first12_count,
  SAFE_DIVIDE(first12_count, eligible_count) * 100 AS first12_pct,
  last24_count,
  SAFE_DIVIDE(last24_count, eligible_count) * 100 AS last24_pct,
  (SAFE_DIVIDE(first12_count, eligible_count) - SAFE_DIVIDE(last24_count, eligible_count)) * 100 AS net_pct_change
FROM (
  SELECT
    COUNT(*) AS eligible_count,
    SUM(CASE
          WHEN EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
            WHERE pr.subject_id = e.subject_id
              AND pr.hadm_id = e.hadm_id
              AND pr.starttime >= e.admittime
              AND pr.starttime < TIMESTAMP_ADD(e.admittime, INTERVAL 12 HOUR)
              AND (
                   LOWER(pr.drug) LIKE '%liraglutide%' OR
                   LOWER(pr.drug) LIKE '%dulaglutide%' OR
                   LOWER(pr.drug) LIKE '%exenatide%' OR
                   LOWER(pr.drug) LIKE '%semaglutide%' OR
                   LOWER(pr.drug) LIKE '%lixisenatide%' OR
                   LOWER(pr.drug) LIKE '%albiglutide%'
                  )
          ) THEN 1 ELSE 0 END
        ) AS first12_count,
    SUM(CASE
          WHEN EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
            WHERE pr.subject_id = e.subject_id
              AND pr.hadm_id = e.hadm_id
              AND pr.starttime >= TIMESTAMP_SUB(e.dischtime, INTERVAL 24 HOUR)
              AND pr.starttime <= e.dischtime
              AND (
                   LOWER(pr.drug) LIKE '%liraglutide%' OR
                   LOWER(pr.drug) LIKE '%dulaglutide%' OR
                   LOWER(pr.drug) LIKE '%exenatide%' OR
                   LOWER(pr.drug) LIKE '%semaglutide%' OR
                   LOWER(pr.drug) LIKE '%lixisenatide%' OR
                   LOWER(pr.drug) LIKE '%albiglutide%'
                  )
          ) THEN 1 ELSE 0 END
        ) AS last24_count
  FROM eligible AS e
) ;