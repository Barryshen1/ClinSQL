WITH admissions_with_diagnosis AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    p.anchor_year
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    di.long_title LIKE '%upper gastrointestinal bleeding%'
    OR di.long_title LIKE '%hematemesis%'
    OR di.long_title LIKE '%melena%'
    OR di.long_title LIKE '%gastrointestinal hemorrhage%'
    OR di.long_title LIKE '%upper GI bleed%'
    OR di.long_title LIKE '%upper GI hemorrhage%'
    OR di.long_title LIKE '%gastric ulcer hemorrhage%'
    OR di.long_title LIKE '%duodenal ulcer hemorrhage%'
    OR di.long_title LIKE '%peptic ulcer hemorrhage%'
    OR di.long_title LIKE '%esophageal hemorrhage%'
    OR di.long_title LIKE '%gastrointestinal bleeding%'
    OR di.long_title LIKE '%hemorrhage%'
),
filtered_admissions AS (
  SELECT
    hadm_id,
    gender,
    anchor_age,
    anchor_year,
    admittime,
    dischtime,
    anchor_age + EXTRACT(YEAR FROM admittime) - anchor_year AS age_at_admission,
    DATE_DIFF(dischtime, admittime, DAY) AS los
  FROM
    admissions_with_diagnosis
  WHERE
    gender = 'F'
    AND (anchor_age + EXTRACT(YEAR FROM admittime) - anchor_year) BETWEEN 53 AND 63
    AND DATE_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 8
),
procedure_counts AS (
  SELECT
    fa.hadm_id,
    CASE
      WHEN fa.los BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN fa.los BETWEEN 5 AND 8 THEN '5-8 days'
    END AS los_group,
    COUNT(pi.seq_num) AS procedure_count
  FROM
    filtered_admissions fa
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON fa.hadm_id = pi.hadm_id
  GROUP BY
    fa.hadm_id, los_group
)
SELECT
  los_group,
  APPROX_QUANTILES(procedure_count, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(procedure_count, 100)[OFFSET(50)] AS p50,
  APPROX_QUANTILES(procedure_count, 100)[OFFSET(75)] AS p75
FROM
  procedure_counts
WHERE
  los_group IS NOT NULL
GROUP BY
  los_group;