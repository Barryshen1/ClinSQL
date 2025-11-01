WITH cohort_admissions AS (
  -- Find all hospital admissions for female patients aged 69-79
  -- who have diagnoses for BOTH COPD exacerbation AND Upper GI Bleed.
  SELECT
    dx.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON dx.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 69 AND 79
  GROUP BY
    dx.hadm_id
  HAVING
    -- Check for presence of a COPD exacerbation diagnosis
    MAX(
      CASE
        WHEN (dx.icd_version = 9 AND dx.icd_code = '49121') -- Obstructive chronic bronchitis w exacerbation
        OR (dx.icd_version = 10 AND dx.icd_code = 'J44.1')   -- COPD w (acute) exacerbation
        THEN 1
        ELSE 0
      END
    ) = 1
    -- AND check for presence of an Upper GI Bleed diagnosis
    AND MAX(
      CASE
        WHEN
          (
            dx.icd_version = 9 AND (
              dx.icd_code IN ('5780', '5781', '5789') -- Hematemesis, Melena, GI hemorrhage unspecified
              OR dx.icd_code LIKE '5310%' -- Gastric ulcer w hemorrhage
              OR dx.icd_code LIKE '5312%' -- Gastric ulcer w hemorrhage and perforation
              OR dx.icd_code LIKE '5314%' -- Chronic gastric ulcer w hemorrhage
              OR dx.icd_code LIKE '5316%' -- Chronic gastric ulcer w hemorrhage and perforation
              OR dx.icd_code LIKE '5320%' -- Duodenal ulcer w hemorrhage
              OR dx.icd_code LIKE '5322%' -- etc.
              OR dx.icd_code LIKE '5324%'
              OR dx.icd_code LIKE '5326%'
              OR dx.icd_code LIKE '5330%' -- Peptic ulcer w hemorrhage
              OR dx.icd_code LIKE '5332%' -- etc.
              OR dx.icd_code LIKE '5334%'
              OR dx.icd_code LIKE '5336%'
              OR dx.icd_code LIKE '5340%' -- Gastrojejunal ulcer w hemorrhage
              OR dx.icd_code LIKE '5342%' -- etc.
              OR dx.icd_code LIKE '5344%'
              OR dx.icd_code LIKE '5346%'
            )
          )
          OR (
            dx.icd_version = 10 AND (
              dx.icd_code IN ('K92.0', 'K92.1', 'K92.2', 'K29.01') -- Hematemesis, Melena, GI hemorrhage, Acute gastritis w bleeding
              OR dx.icd_code LIKE 'K25.0%' -- Gastric ulcer w hemorrhage
              OR dx.icd_code LIKE 'K25.2%' -- etc. w perf
              OR dx.icd_code LIKE 'K25.4%'
              OR dx.icd_code LIKE 'K25.6%'
              OR dx.icd_code LIKE 'K26.0%' -- Duodenal ulcer w hemorrhage
              OR dx.icd_code LIKE 'K26.2%' -- etc.
              OR dx.icd_code LIKE 'K26.4%'
              OR dx.icd_code LIKE 'K26.6%'
              OR dx.icd_code LIKE 'K27.0%' -- Peptic ulcer w hemorrhage
              OR dx.icd_code LIKE 'K27.2%' -- etc.
              OR dx.icd_code LIKE 'K27.4%'
              OR dx.icd_code LIKE 'K27.6%'
              OR dx.icd_code LIKE 'K28.0%' -- Gastrojejunal ulcer w hemorrhage
              OR dx.icd_code LIKE 'K28.2%' -- etc.
              OR dx.icd_code LIKE 'K28.4%'
              OR dx.icd_code LIKE 'K28.6%'
            )
          )
        THEN 1
        ELSE 0
      END
    ) = 1
)
-- Calculate the median hospital length of stay for the identified cohort
SELECT
  PERCENTILE_CONT(
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY),
    0.5
  ) OVER() AS median_hospital_los_days
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
INNER JOIN
  cohort_admissions AS cohort
  ON adm.hadm_id = cohort.hadm_id
WHERE
  adm.dischtime IS NOT NULL AND adm.admittime IS NOT NULL
LIMIT 1;