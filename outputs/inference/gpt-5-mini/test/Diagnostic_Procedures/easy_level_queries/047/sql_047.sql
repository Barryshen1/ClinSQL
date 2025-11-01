WITH male_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
),

matching_proc_counts AS (
  -- count distinct matching procedure codes per admission
  SELECT
    pr.hadm_id,
    COUNT(DISTINCT CONCAT(pr.icd_version, '_', pr.icd_code)) AS proc_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
      ON pr.icd_code = dp.icd_code
      AND pr.icd_version = dp.icd_version
  WHERE
    -- look for ablation or cardioversion in the procedure description
    -- lower(NULL) yields NULL and REGEXP_CONTAINS(NULL, ...) -> FALSE, so safe
    REGEXP_CONTAINS(LOWER(COALESCE(dp.long_title, '')), r'(ablat|cardiov)')
  GROUP BY
    pr.hadm_id
)

SELECT
  COUNT(1) AS n_admissions_in_age_group,
  ROUND(STDDEV_SAMP(proc_cnt), 6) AS sd_distinct_ablation_or_cardioversion_per_admission
FROM (
  -- include admissions with zero matching procedures
  SELECT
    m.hadm_id,
    COALESCE(mp.proc_count, 0) AS proc_cnt
  FROM
    male_admissions m
    LEFT JOIN matching_proc_counts mp
      ON m.hadm_id = mp.hadm_id
);