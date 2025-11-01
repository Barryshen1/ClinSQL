SELECT
  STDDEV(peak_potassium) AS std_dev_peak_serum_potassium
FROM (
  SELECT
    ie.stay_id,
    MAX(le.valuenum) AS peak_potassium
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN
    physionet-data.mimiciv_3_1_icu.icustays ie
    ON p.subject_id = ie.subject_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.labevents le
    ON ie.hadm_id = le.hadm_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems dli
    ON le.itemid = dli.itemid
  WHERE
    p.gender = 'M'
    AND p.anchor_age = 56
    AND LOWER(dli.label) = 'potassium'
    AND LOWER(dli.fluid) = 'blood'
    AND le.charttime >= ie.intime
    AND (le.charttime <= ie.outtime OR ie.outtime IS NULL)
    AND le.valuenum IS NOT NULL
  GROUP BY
    ie.stay_id
) AS stay_peaks;