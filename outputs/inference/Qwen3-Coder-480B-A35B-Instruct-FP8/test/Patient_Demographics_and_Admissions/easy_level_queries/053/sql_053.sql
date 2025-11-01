WITH cohort AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.dischtime IS NOT NULL
    AND (
      (d.icd_version = 9 AND dd.icd_code LIKE '584%') OR
      (d.icd_version = 10 AND dd.icd_code LIKE 'N17%')
    )
),

readmit_flag AS (
  SELECT
    c1.hadm_id,
    CASE
      WHEN MIN(c2.admittime) BETWEEN c1.dischtime AND DATETIME_ADD(c1.dischtime, INTERVAL 30 DAY)
      THEN 1
      ELSE 0
    END AS readmit_30
  FROM
    cohort c1
  LEFT JOIN
    cohort c2
    ON c1.subject_id = c2.subject_id
    AND c2.admittime > c1.dischtime
  GROUP BY
    c1.hadm_id, c1.dischtime
)

SELECT
  STDDEV(readmit_30) AS std_readmit_30
FROM
  readmit_flag;