SELECT
  APPROX_QUANTILES(hospital_expire_flag, 4)[OFFSET(1)] AS mortality_25th_percentile
FROM (
  SELECT
    a.hospital_expire_flag
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  JOIN (
    SELECT
      subject_id,
      hadm_id,
      admittime,
      hospital_expire_flag,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime ASC) AS rn
    FROM
      physionet-data.mimiciv_3_1_hosp.admissions
  ) a
    ON p.subject_id = a.subject_id
  WHERE
    a.rn = 1
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
);