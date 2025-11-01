WITH
-- Get male patients aged 83-93
eligible_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 83 AND 93
),

-- Get admissions with ACS diagnosis (I20-I25)
acs_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    d.seq_num,
    CASE WHEN d.seq_num = 1 THEN 'Primary' ELSE 'Secondary' END AS diagnosis_type,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS length_of_stay_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    eligible_patients p
  ON
    a.subject_id = p.subject_id
  WHERE
    d.icd_code LIKE 'I2%'
    AND a.hadm_id IS NOT NULL
),

-- Get ultrasound procedures (using HCPCS codes)
ultrasound_procedures AS (
  SELECT
    subject_id,
    hadm_id,
    COUNT(*) AS ultrasound_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
  WHERE
    hcpcs_cd IN (
      '76700', '76705', '76770', '76775', '76801', '76802', '76815', '76816', '76817', '76818',
      '76825', '76826', '76827', '76828', '76856', '76857', '76870', '76871', '76872', '76881',
      '76882', '76930', '76937', '76942', '76970', '76978', '76980', '76981', '76982', '76985',
      '76986', '76988', '76990', '76998', '76999', '77001', '77002', '77003', '77012', '77013',
      '77014', '77021', '77022', '77031', '77032', '77033', '77034', '77035', '77036', '77037',
      '77038', '77039', '77040', '77041', '77042', '77043', '77044', '77045', '77046', '77047',
      '77048', '77049', '77051', '77052', '77053', '77054', '77055', '77056', '77057', '77058',
      '77059', '77061', '77062', '77063', '77064', '77065', '77066', '77067', '77068', '77069',
      '77071', '77072', '77073', '77074', '77075', '77076', '77077', '77078', '77079', '77080',
      '77081', '77082', '77083', '77084', '77085', '77086', '77087', '77088', '77089', '77090',
      '77091', '77092', '77093', '77094', '77095', '77096', '77097', '77098', '77099'
    )
  GROUP BY
    subject_id, hadm_id
)

-- Final aggregation
SELECT
  diagnosis_type,
  CASE
    WHEN length_of_stay_days BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN length_of_stay_days BETWEEN 5 AND 7 THEN '5-7 days'
    ELSE 'Other'
  END AS length_of_stay_group,
  COUNT(DISTINCT a.hadm_id) AS admission_count,
  AVG(COALESCE(u.ultrasound_count, 0)) AS mean_ultrasounds,
  MIN(COALESCE(u.ultrasound_count, 0)) AS min_ultrasounds,
  MAX(COALESCE(u.ultrasound_count, 0)) AS max_ultrasounds
FROM
  acs_admissions a
LEFT JOIN
  ultrasound_procedures u
ON
  a.subject_id = u.subject_id AND a.hadm_id = u.hadm_id
WHERE
  length_of_stay_days BETWEEN 1 AND 7
GROUP BY
  diagnosis_type, length_of_stay_group
ORDER BY
  diagnosis_type, length_of_stay_group;