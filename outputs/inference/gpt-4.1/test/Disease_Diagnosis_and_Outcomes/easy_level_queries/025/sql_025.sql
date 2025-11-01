WITH upper_gi_bleed_codes AS (
  -- List of ICD codes for upper GI bleeding (ICD-9 and ICD-10)
  SELECT 'K920' AS icd_code, 10 AS icd_version UNION ALL -- Hematemesis
  SELECT 'K921', 10 UNION ALL -- Melena
  SELECT 'K250', 10 UNION ALL -- Gastric ulcer with hemorrhage
  SELECT 'K251', 10 UNION ALL
  SELECT 'K252', 10 UNION ALL
  SELECT 'K253', 10 UNION ALL
  SELECT 'K254', 10 UNION ALL
  SELECT 'K255', 10 UNION ALL
  SELECT 'K256', 10 UNION ALL
  SELECT 'K257', 10 UNION ALL
  SELECT 'K258', 10 UNION ALL
  SELECT 'K259', 10 UNION ALL
  SELECT 'K260', 10 UNION ALL -- Duodenal ulcer with hemorrhage
  SELECT 'K261', 10 UNION ALL
  SELECT 'K262', 10 UNION ALL
  SELECT 'K263', 10 UNION ALL
  SELECT 'K264', 10 UNION ALL
  SELECT 'K265', 10 UNION ALL
  SELECT 'K266', 10 UNION ALL
  SELECT 'K267', 10 UNION ALL
  SELECT 'K268', 10 UNION ALL
  SELECT 'K269', 10 UNION ALL
  SELECT 'K270', 10 UNION ALL -- Peptic ulcer with hemorrhage
  SELECT 'K271', 10 UNION ALL
  SELECT 'K272', 10 UNION ALL
  SELECT 'K273', 10 UNION ALL
  SELECT 'K274', 10 UNION ALL
  SELECT 'K275', 10 UNION ALL
  SELECT 'K276', 10 UNION ALL
  SELECT 'K277', 10 UNION ALL
  SELECT 'K278', 10 UNION ALL
  SELECT 'K279', 10 UNION ALL
  SELECT 'K280', 10 UNION ALL -- Gastrojejunal ulcer with hemorrhage
  SELECT 'K281', 10 UNION ALL
  SELECT 'K282', 10 UNION ALL
  SELECT 'K283', 10 UNION ALL
  SELECT 'K284', 10 UNION ALL
  SELECT 'K285', 10 UNION ALL
  SELECT 'K286', 10 UNION ALL
  SELECT 'K287', 10 UNION ALL
  SELECT 'K288', 10 UNION ALL
  SELECT 'K289', 10 UNION ALL
  SELECT 'I850', 10 UNION ALL -- Esophageal varices with bleeding
  SELECT 'K226', 10 UNION ALL -- Dieulafoy lesion of esophagus
  SELECT 'K2971', 10 UNION ALL -- Acute gastritis with bleeding
  SELECT 'K31811', 10 UNION ALL -- Angiodysplasia of stomach/duodenum with bleeding
  -- ICD-9 codes
  SELECT '5780', 9 UNION ALL -- Hematemesis
  SELECT '5781', 9 UNION ALL -- Blood in stool
  SELECT '5789', 9 UNION ALL -- GI hemorrhage, unspecified
  SELECT '53100', 9 UNION ALL -- Gastric ulcer with hemorrhage
  SELECT '53101', 9 UNION ALL
  SELECT '53120', 9 UNION ALL
  SELECT '53121', 9 UNION ALL
  SELECT '53200', 9 UNION ALL -- Duodenal ulcer with hemorrhage
  SELECT '53201', 9 UNION ALL
  SELECT '53220', 9 UNION ALL
  SELECT '53221', 9 UNION ALL
  SELECT '53300', 9 UNION ALL -- Peptic ulcer with hemorrhage
  SELECT '53301', 9 UNION ALL
  SELECT '53320', 9 UNION ALL
  SELECT '53321', 9 UNION ALL
  SELECT '53400', 9 UNION ALL -- Gastrojejunal ulcer with hemorrhage
  SELECT '53401', 9 UNION ALL
  SELECT '53420', 9 UNION ALL
  SELECT '53421', 9 UNION ALL
  SELECT '4560', 9 -- Esophageal varices with bleeding
)

SELECT
  STDDEV_SAMP(los_days) AS sd_los_days
FROM (
  SELECT
    a.subject_id,
    a.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    INNER JOIN upper_gi_bleed_codes ugb
      ON d.icd_code = ugb.icd_code AND d.icd_version = ugb.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    AND d.seq_num = 1 -- primary diagnosis
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)
WHERE
  los_days > 0;