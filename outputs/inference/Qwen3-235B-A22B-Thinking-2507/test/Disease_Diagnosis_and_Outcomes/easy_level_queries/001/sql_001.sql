WITH eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients
  WHERE gender = 'M'
    AND anchor_age BETWEEN 86 AND 96
),
ugib_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd
  WHERE 
    (icd_version = 10 AND icd_code IN (
      'K250', 'K251', 'K252', 'K253', 'K254', 'K255', 'K256', 'K257',
      'K260', 'K261', 'K262', 'K263', 'K264', 'K265', 'K266', 'K267',
      'K270', 'K271', 'K272', 'K273', 'K274', 'K275', 'K276', 'K277',
      'K280', 'K281', 'K282', 'K283', 'K284', 'K285', 'K286', 'K287',
      'K920', 'K921', 'K922'
    ))
    OR
    (icd_version = 9 AND icd_code IN (
      '53020', '53021', '53022', '53023', '53024', '53025', '53026', '53027',
      '53100', '53101', '53110', '53111', '53120', '53121', '53130', '53131', '53140', '53141', '53150', '53151', '53160', '53161', '53170', '53171',
      '53200', '53201', '53210', '53211', '53220', '53221', '53230', '53231', '53240', '53241', '53250', '53251', '53260', '53261', '53270', '53271',
      '53300', '53301', '53310', '53311', '53320', '53321', '53330', '53331', '53340', '53341', '53350', '53351', '53360', '53361', '53370', '53371',
      '53400', '53401', '53410', '53411', '53420', '53421', '53430', '53431', '53440', '53441', '53450', '53451', '53460', '53461', '53470', '53471',
      '5780'
    ))
),
copd_exac_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd
  WHERE 
    (icd_version = 10 AND icd_code = 'J441')
    OR
    (icd_version = 9 AND icd_code IN ('49121', '49122'))
),
eligible_admissions AS (
  SELECT a.hadm_id, 
         TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN eligible_patients p ON a.subject_id = p.subject_id
  INNER JOIN ugib_admissions u ON a.hadm_id = u.hadm_id
  INNER JOIN copd_exac_admissions c ON a.hadm_id = c.hadm_id
)
SELECT AVG(los_days) AS avg_los
FROM eligible_admissions;