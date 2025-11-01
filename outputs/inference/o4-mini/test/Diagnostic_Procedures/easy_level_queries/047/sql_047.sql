SELECT
  STDDEV_POP(proc_count) AS stddev_distinct_procs
FROM (
  SELECT
    a.hadm_id,
    COUNT(DISTINCT
      CASE
        WHEN LOWER(d.long_title) LIKE '%ablation%'
          OR LOWER(d.long_title) LIKE '%cardioversion%'
        THEN p.icd_code
      END
    ) AS proc_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` pt
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON pt.subject_id = a.subject_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
      ON a.subject_id = p.subject_id
      AND a.hadm_id = p.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
      ON p.icd_code = d.icd_code
      AND p.icd_version = d.icd_version
  WHERE
    pt.gender = 'M'
    AND pt.anchor_age BETWEEN 37 AND 47
  GROUP BY
    a.hadm_id
);