SELECT
      i.subject_id,
      i.hadm_id,
      i.stay_id,
      i.intime,
      i.outtime,
      i.mortality,
      i.age,
      i.gender,
      NULL AS vital_instability_index,
      NULL AS tachycardia_burden,
      NULL AS map65_burden
    FROM
      icu_stays_with_demo i
    LEFT JOIN cohort_specific cs
      ON i.subject_id = cs.subject_id
      AND i.hadm_id = cs.hadm_id
      AND i.stay_id = cs.stay_id
    WHERE
      cs.subject_id IS NULL
  );