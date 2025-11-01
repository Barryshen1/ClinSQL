SELECT STDDEV_POP(TIMESTAMP_DIFF(stoptime, starttime, DAY)) AS sd_nitrate_duration_days
FROM physionet-data.mimiciv_3_1_hosp.prescriptions p
JOIN physionet-data.mimiciv_3_1_hosp.patients pat
  ON p.subject_id = pat.subject_id
WHERE pat.gender = 'F'
  AND pat.anchor_age BETWEEN 73 AND 83
  AND (LOWER(p.drug) LIKE '%nitro%' OR LOWER(p.drug) LIKE '%isosorbide%')
  AND p.starttime IS NOT NULL
  AND p.stoptime IS NOT NULL
  AND p.stoptime >= p.starttime;