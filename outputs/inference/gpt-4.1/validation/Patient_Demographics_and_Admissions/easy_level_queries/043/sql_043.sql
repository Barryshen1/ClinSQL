SELECT
  quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS in_hospital_mortality_IQR
FROM (
  SELECT
    APPROX_QUANTILES(hospital_expire_flag, 4) AS quantiles
  FROM (
    SELECT
      adm.hospital_expire_flag
    FROM
      physionet-data.mimiciv_3_1_hosp.admissions AS adm
    JOIN
      physionet-data.mimiciv_3_1_hosp.patients AS pat
    ON
      adm.subject_id = pat.subject_id
    WHERE
      pat.gender = 'F'
      AND pat.anchor_age BETWEEN 51 AND 61
  )
);