WITH mcs_procs_per_adm AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    COUNT(DISTINCT pc.icd_code) AS mcs_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    USING(subject_id)
  JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pc
    ON pc.hadm_id = a.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON pc.icd_code = dp.icd_code
    AND pc.icd_version = dp.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 80 AND 90
    AND (
      COALESCE(LOWER(dp.long_title), '') LIKE '%assist%' OR
      COALESCE(LOWER(dp.long_title), '') LIKE '%ventricular%' OR
      COALESCE(LOWER(dp.long_title), '') LIKE '%ventricular assist%' OR
      COALESCE(LOWER(dp.long_title), '') LIKE '%ventricular assist device%' OR
      COALESCE(LOWER(dp.long_title), '') LIKE '%intra-aortic balloon%' OR
      COALESCE(LOWER(dp.long_title), '') LIKE '%ecmo%' OR
      COALESCE(LOWER(dp.long_title), '') LIKE '%extracorporeal%' OR
      COALESCE(LOWER(dp.long_title), '') LIKE '%cardiac assist%' OR
      COALESCE(LOWER(dp.long_title), '') LIKE '%venoarterial%' OR
      COALESCE(LOWER(dp.long_title), '') LIKE '%venovenous%'
    )
  GROUP BY
    p.subject_id,
    a.hadm_id
)

SELECT
  MAX(mcs_count) AS max_distinct_mcs_procedures,
  -- example admissions that achieve the top counts (up to 10)
  ARRAY_AGG(STRUCT(subject_id, hadm_id, mcs_count) ORDER BY mcs_count DESC LIMIT 10) AS top_examples
FROM
  mcs_procs_per_adm;