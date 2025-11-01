WITH upper_gi_bleed_codes AS (
  -- List of ICD-10 codes for upper GI bleeding
  SELECT 'K92.0' AS icd_code UNION ALL
  SELECT 'K92.1' UNION ALL
  SELECT 'K92.2' UNION ALL
  SELECT 'K25.0' UNION ALL -- gastric ulcer, acute with hemorrhage
  SELECT 'K25.2' UNION ALL -- gastric ulcer, acute with both hemorrhage and perforation
  SELECT 'K25.4' UNION ALL -- gastric ulcer, chronic or unspecified with hemorrhage
  SELECT 'K25.6' UNION ALL -- gastric ulcer, chronic or unspecified with both hemorrhage and perforation
  SELECT 'K26.0' UNION ALL -- duodenal ulcer, acute with hemorrhage
  SELECT 'K26.2' UNION ALL -- duodenal ulcer, acute with both hemorrhage and perforation
  SELECT 'K26.4' UNION ALL -- duodenal ulcer, chronic or unspecified with hemorrhage
  SELECT 'K26.6' UNION ALL -- duodenal ulcer, chronic or unspecified with both hemorrhage and perforation
  SELECT 'K27.0' UNION ALL -- peptic ulcer, acute with hemorrhage
  SELECT 'K27.2' UNION ALL -- peptic ulcer, acute with both hemorrhage and perforation
  SELECT 'K27.4' UNION ALL -- peptic ulcer, chronic or unspecified with hemorrhage
  SELECT 'K27.6' UNION ALL -- peptic ulcer, chronic or unspecified with both hemorrhage and perforation
  SELECT 'K28.0' UNION ALL -- gastrojejunal ulcer, acute with hemorrhage
  SELECT 'K28.2' UNION ALL -- gastrojejunal ulcer, acute with both hemorrhage and perforation
  SELECT 'K28.4' UNION ALL -- gastrojejunal ulcer, chronic or unspecified with hemorrhage
  SELECT 'K28.6'           -- gastrojejunal ulcer, chronic or unspecified with both hemorrhage and perforation
)

SELECT
  PERCENTILE_CONT(los_days, 0.75) OVER () AS los_75th_percentile_days
FROM (
  SELECT
    a.hadm_id,
    a.subject_id,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN
    upper_gi_bleed_codes ugb
    ON d.icd_code = ugb.icd_code AND d.icd_version = 10
  WHERE
    p.gender = 'M'
    AND p.anchor_age = 70
    AND d.seq_num = 1 -- primary diagnosis
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND DATETIME_DIFF(a.dischtime, a.admittime, DAY) > 0
);