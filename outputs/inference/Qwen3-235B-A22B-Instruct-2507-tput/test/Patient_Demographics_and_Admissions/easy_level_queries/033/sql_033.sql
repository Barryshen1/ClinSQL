SELECT
  STDDEV(los_days) AS sd_los_days
FROM (
  SELECT
    a.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / (24 * 60 * 60) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON
    p.subject_id = a.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu`.procedureevents pe
  ON
    a.hadm_id = pe.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu`.d_items di
  ON
    pe.itemid = di.itemid
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
    AND LOWER(di.label) LIKE '%dialysis%'
);