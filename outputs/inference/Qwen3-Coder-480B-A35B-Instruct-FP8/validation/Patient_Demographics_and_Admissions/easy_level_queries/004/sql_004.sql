WITH first_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  WHERE
    a.subject_id IN (
      SELECT subject_id
      FROM physionet-data.mimiciv_3_1_hosp.patients
      WHERE gender = 'F'
        AND anchor_age BETWEEN 70 AND 80
    )
  QUALIFY ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) = 1
)
SELECT
  STDDEV_SAMP(i.los) AS los_sd_days
FROM
  first_admissions fa
JOIN
  physionet-data.mimiciv_3_1_icu.icustays i
ON
  fa.hadm_id = i.hadm_id;