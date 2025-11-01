SELECT
  APPROX_QUANTILES(duration_days, 1000)[OFFSET(750)] AS percentile_75_duration_days
FROM (
  SELECT
    (DATETIME_DIFF(CAST(p.stoptime AS DATETIME), CAST(p.starttime AS DATETIME), SECOND)) / (24 * 3600.0) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients pats
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions adm
    ON pats.subject_id = adm.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.prescriptions p
    ON adm.hadm_id = p.hadm_id
  WHERE
    pats.gender = 'M'
    AND p.drug_type = 'INPATIENT'
    AND LOWER(p.drug) IN (
      'losartan', 'valsartan', 'irbesartan', 'candesartan',
      'telmisartan', 'olmesartan', 'eprosartan'
    )
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND p.stoptime > p.starttime
    AND (
      pats.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pats.anchor_year)
    ) BETWEEN 38 AND 48
);