WITH cohort AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.dod,
    MAX(CASE WHEN d_icd.long_title LIKE '%ketoacidosis%' THEN 1 ELSE 0 END) AS has_dka,
    MAX(CASE WHEN d_icd.long_title LIKE '%myocardial infarction%' 
              OR d_icd.long_title LIKE '%heart failure%' 
              OR d_icd.long_title LIKE '%coronary artery disease%' 
              THEN 1 ELSE 0 END) AS has_cardiovascular_complication,
    MAX(CASE WHEN d_icd.long_title LIKE '%stroke%' 
              OR d_icd.long_title LIKE '%cerebrovascular accident%' 
              OR d_icd.long_title LIKE '%seizure%' 
              THEN 1 ELSE 0 END) AS has_neurologic_complication,
    CASE
      WHEN a.hospital_expire_flag = 0 THEN EXTRACT(DAY FROM (a.dischtime - a.admittime))
      ELSE NULL
    END AS los_survivor,
    CASE
      WHEN p.dod IS NOT NULL AND p.dod <= a.dischtime + INTERVAL '30' DAY THEN 1
      ELSE 0
    END AS thirty_day_mortality
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
  GROUP BY
    a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag, p.dod
)
SELECT
  has_dka,
  AVG(thirty_day_mortality) AS thirty_day_mortality_rate,
  AVG(has_cardiovascular_complication) AS cardiovascular_complication_rate,
  AVG(has_neurologic_complication) AS neurologic_complication_rate,
  AVG(los_survivor) AS mean_survivor_los
FROM
  cohort
GROUP BY
  has_dka;