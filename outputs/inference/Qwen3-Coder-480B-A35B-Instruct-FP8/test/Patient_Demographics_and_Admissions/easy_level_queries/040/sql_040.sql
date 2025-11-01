SELECT
  APPROX_QUANTILES(los, 2)[OFFSET(1)] AS median_icu_los
FROM
  physionet-data.mimiciv_3_1_icu.icustays icu
JOIN
  physionet-data.mimiciv_3_1_hosp.patients pat
  ON icu.subject_id = pat.subject_id
WHERE
  pat.gender = 'F'
  AND pat.anchor_age BETWEEN 35 AND 45;