WITH ugi_bleed_admissions AS (
  SELECT
    adm.hadm_id,
    DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.hadm_id = dx.hadm_id
  WHERE
    -- 1. Filter for male patients aged 77-87
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 77 AND 87
    -- 2. Filter for primary diagnosis
    AND dx.seq_num = 1
    -- 3. Filter for admissions with an upper GI bleeding diagnosis
    AND (
      -- ICD-9 codes
      dx.icd_code LIKE '578%' -- Gastrointestinal hemorrhage
      OR dx.icd_code LIKE '5310%' -- Acute gastric ulcer with hemorrhage
      OR dx.icd_code LIKE '5312%' -- Acute gastric ulcer with hemorrhage and perforation
      OR dx.icd_code LIKE '5314%' -- Chronic or unspec. gastric ulcer with hemorrhage
      OR dx.icd_code LIKE '5316%' -- Chronic or unspec. gastric ulcer with hemorrhage and perforation
      OR dx.icd_code LIKE '5320%' -- Acute duodenal ulcer with hemorrhage
      OR dx.icd_code LIKE '5322%' -- Acute duodenal ulcer with hemorrhage and perforation
      OR dx.icd_code LIKE '5324%' -- Chronic or unspec. duodenal ulcer with hemorrhage
      OR dx.icd_code LIKE '5326%' -- Chronic or unspec. duodenal ulcer with hemorrhage and perforation
      OR dx.icd_code LIKE '5330%' -- Acute peptic ulcer with hemorrhage
      OR dx.icd_code LIKE '5332%' -- Acute peptic ulcer with hemorrhage and perforation
      OR dx.icd_code LIKE '5334%' -- Chronic or unspec. peptic ulcer with hemorrhage
      OR dx.icd_code LIKE '5336%' -- Chronic or unspec. peptic ulcer with hemorrhage and perforation
      OR dx.icd_code LIKE '5340%' -- Acute gastrojejunal ulcer with hemorrhage
      OR dx.icd_code LIKE '5342%' -- Acute gastrojejunal ulcer with hemorrhage and perforation
      OR dx.icd_code LIKE '5344%' -- Chronic or unspec. gastrojejunal ulcer with hemorrhage
      OR dx.icd_code LIKE '5346%' -- Chronic or unspec. gastrojejunal ulcer with hemorrhage and perforation

      -- ICD-10 codes
      OR dx.icd_code IN (
        'K920', -- Hematemesis
        'K921', -- Melena
        'K922', -- Gastrointestinal hemorrhage, unspecified
        'K250', -- Acute gastric ulcer with hemorrhage
        'K252', -- Acute gastric ulcer with hemorrhage and perforation
        'K254', -- Chronic or unspecified gastric ulcer with hemorrhage
        'K256', -- Chronic or unspecified gastric ulcer with hemorrhage and perforation
        'K260', -- Acute duodenal ulcer with hemorrhage
        'K262', -- Acute duodenal ulcer with hemorrhage and perforation
        'K264', -- Chronic or unspecified duodenal ulcer with hemorrhage
        'K266', -- Chronic or unspecified duodenal ulcer with hemorrhage and perforation
        'K270', -- Acute peptic ulcer with hemorrhage
        'K272', -- Acute peptic ulcer with hemorrhage and perforation
        'K274', -- Chronic or unspecified peptic ulcer with hemorrhage
        'K276', -- Chronic or unspecified peptic ulcer with hemorrhage and perforation
        'K280', -- Acute gastrojejunal ulcer with hemorrhage
        'K282', -- Acute gastrojejunal ulcer with hemorrhage and perforation
        'K284', -- Chronic or unspecified gastrojejunal ulcer with hemorrhage
        'K286' -- Chronic or unspecified gastrojejunal ulcer with hemorrhage and perforation
      )
    )
)
SELECT
  STDDEV(los_days) AS los_sd_days
FROM
  ugi_bleed_admissions;