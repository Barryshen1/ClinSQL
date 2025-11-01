WITH AKI_Admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.los,
    d.long_title AS diagnosis_title,
    d.icd_version AS icd_version,
    CASE
      WHEN di.seq_num = 1 THEN 'Primary'
      ELSE 'Secondary'
    END AS aki_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.hadm_id = di.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
    ON di.icd_code = d.icd_code
    AND di.icd_version = d.icd_version
  WHERE
    (
      di.icd_code LIKE 'N17%'
      OR di.icd_code LIKE 'I12%'
    )
    AND a.subject_id IN (
      SELECT
        subject_id
      FROM
        `physionet-data.mimiciv_3_1_hosp.patients`
      WHERE
        gender = 'M'
        AND anchor_age = 48
    )
    AND a.anchor_age BETWEEN 43 AND 53
), Imaging_Counts AS (
  SELECT
    a.hadm_id,
    COUNT(DISTINCT hc.hcpcs_cd) AS imaging_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` AS hc
    ON a.hadm_id = hc.hadm_id
  WHERE
    hc.hcpcs_cd IN (
      '7700211',
      '7700311',
      '77059',
      '77061',
      '77062',
      '77063',
      '77067',
      '77068',
      '77069',
      '77071',
      '77072',
      '77073',
      '77074',
      '77075',
      '77076',
      '77077',
      '77078',
      '77079',
      '77080',
      '77081',
      '77082',
      '77083',
      '77084',
      '77085',
      '77086',
      '77087',
      '77088',
      '77089',
      '77090',
      '77091',
      '77092',
      '77093',
      '77094'
    )
)
SELECT
  aki.aki_type,
  CASE
    WHEN aki.los BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN aki.los BETWEEN 5 AND 7 THEN '5-7 days'
    ELSE 'Other'
  END AS los_category,
  COUNT(DISTINCT aki.subject_id) AS patient_count,
  AVG(img.imaging_count) AS mean_imaging_count
FROM
  AKI_Admissions AS aki
LEFT JOIN
  Imaging_Counts AS img
  ON aki.hadm_id = img.hadm_id
GROUP BY
  aki.aki_type,
  los_category
ORDER BY
  aki.aki_type,
  los_category;