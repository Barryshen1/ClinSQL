WITH cohort AS (
  SELECT DISTINCT
    a.hadm_id,
    i.los
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  JOIN
    physionet-data.mimiciv_3_1_icu.icustays i
    ON a.hadm_id = i.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
    AND i.los BETWEEN 1 AND 8
    AND dd.icd_code IN (
      'K250', 'K252', 'K254', 'K256',
      'K260', 'K262', 'K264', 'K266',
      'K270', 'K272', 'K274', 'K276',
      'K280', 'K282', 'K284', 'K286',
      'K922'
    )
    AND dd.icd_version = 10
),

procedure_counts AS (
  SELECT
    c.hadm_id,
    c.los,
    COUNT(pr.icd_code) AS proc_count
  FROM
    cohort c
  LEFT JOIN
    physionet-data.mimiciv_3_1_hosp.procedures_icd pr
    ON c.hadm_id = pr.hadm_id
  GROUP BY
    c.hadm_id, c.los
),

los_groups AS (
  SELECT
    hadm_id,
    proc_count,
    CASE
      WHEN los BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN los BETWEEN 5 AND 8 THEN '5-8 days'
    END AS los_group
  FROM
    procedure_counts
)

SELECT
  los_group,
  APPROX_QUANTILES(proc_count, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(proc_count, 100)[OFFSET(50)] AS p50,
  APPROX_QUANTILES(proc_count, 100)[OFFSET(75)] AS p75
FROM
  los_groups
GROUP BY
  los_group
ORDER BY
  los_group;