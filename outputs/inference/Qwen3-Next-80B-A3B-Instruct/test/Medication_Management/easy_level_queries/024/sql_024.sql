SELECT MAX(ph.duration) AS max_dapt_duration
FROM physionet-data.mimiciv_3_1_hosp.pharmacy ph
JOIN physionet-data.mimiciv_3_1_hosp.patients pat
  ON ph.subject_id = pat.subject_id
WHERE pat.gender = 'M'
  AND pat.anchor_age BETWEEN 84 AND 94
  AND LOWER(ph.medication) IN ('aspirin', 'clopidogrel', 'ticagrelor', 'prasugrel');