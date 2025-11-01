SELECT
  STDDEV(DATETIME_DIFF(admissions.dischtime, admissions.admittime, HOUR) / 24.0) AS sd_los_days
FROM
  physionet-data.mimiciv_3_1_hosp.admissions
JOIN
  physionet-data.mimiciv_3_1_hosp.patients
  ON admissions.subject_id = patients.subject_id
WHERE
  patients.gender = 'M'
  AND patients.anchor_age BETWEEN 44 AND 54
  AND admissions.hadm_id IN (
    SELECT DISTINCT hadm_id
    FROM physionet-data.mimiciv_3_1_icu.procedureevents
    JOIN physionet-data.mimiciv_3_1_icu.d_items
      ON procedureevents.itemid = d_items.itemid
    WHERE LOWER(d_items.label) LIKE '%dialysis%'
  );