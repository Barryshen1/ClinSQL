SELECT STDDEV(DISTINCT TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)) AS sd_length_of_stay_days
FROM physionet-data.mimiciv_3_1_hosp.patients p
JOIN physionet-data.mimiciv_3_1_hosp.admissions a
  ON p.subject_id = a.subject_id
WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 44 AND 54
  AND EXISTS (
    SELECT 1
    FROM physionet-data.mimiciv_3_1_icu.procedureevents pe
    JOIN physionet-data.mimiciv_3_1_icu.d_items di
      ON pe.itemid = di.itemid
    WHERE pe.hadm_id = a.hadm_id
      AND LOWER(di.label) LIKE '%dialysis%'
  );