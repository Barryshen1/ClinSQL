WITH nitrate_prescriptions AS (
  SELECT
    DATETIME_DIFF(pres.stoptime, pres.starttime, SECOND) / 86400.0 AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` pt
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON pt.subject_id = adm.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
    ON adm.hadm_id = pres.hadm_id
  WHERE
    pt.gender = 'F'
    AND (pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year)) BETWEEN 73 AND 83
    AND pres.starttime IS NOT NULL
    AND pres.stoptime IS NOT NULL
    AND pres.stoptime >= pres.starttime
    AND (
      LOWER(pres.drug) LIKE '%nitrate%'
      OR LOWER(pres.drug) LIKE '%nitroglycerin%'
      OR LOWER(pres.drug) LIKE '%isosorbide%'
    )
)
SELECT
  STDDEV_SAMP(duration_days) AS sd_duration_days
FROM
  nitrate_prescriptions;